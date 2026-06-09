`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: topsoft
// 檔案名稱: topsoft.v
// 功能描述:
//   Crystals-Dilithium 硬體加速器的 AXI-Stream 頂層封裝模組 (Top Wrapper)。
//   本模組封裝了前向 NTT、逆向 INTT、點對點相乘 PWM 三大核心，並內建
//   雙埠記憶體緩衝區 (RAM A, B, C) 用以儲存多項式係數。
//   透過 GPIO 控制訊號 (ctrl_op)，加速器在不同的狀態機中切換，
//   與標準的 Xilinx AXI DMA 進行 64-bit 高速雙通道資料傳輸與互動。
//
// 控制編碼 (ctrl_op):
//   00 (2'b00): 前向 NTT 轉換 (時域 -> 頻域)
//   01 (2'b01): 逆向 INTT 轉換與 N^-1 縮放 (頻域 -> 時域)
//   10 (2'b10): 頻域點對點多項式相乘 (PWM)
// =============================================================================

module topsoft (
    input  wire        aclk,          // AXI 高速系統時鐘
    input  wire        aresetn,       // AXI 低電平復位訊號
    
    // GPIO 模式控制 (自 Zynq PS 端的 AXI GPIO 控制器接入)
    input  wire [4:0]  ctrl_op,
    
    // AXI-Stream Slave 介面 (由 AXI DMA 寫入多項式資料至加速器)
    input  wire [63:0] s_axis_tdata,  // 64-bit 寬度：[22:0] 為通道 1，[54:32] 為通道 2
    input  wire        s_axis_tvalid, // DMA 發送有效訊號
    output reg         s_axis_tready, // 加速器接收準備就緒訊號
    input  wire        s_axis_tlast,  // DMA 發送最後一拍指示
    
    // AXI-Stream Master 介面 (將加速器運算結果送回 AXI DMA)
    output reg  [63:0] m_axis_tdata,  // 64-bit 傳輸分量
    output reg         m_axis_tvalid, // 加速器輸出有效訊號
    input  wire        m_axis_tready, // DMA 接收準備就緒訊號
    output reg         m_axis_tlast   // 加速器傳輸結束最後一拍指示
);

    // ==========================================
    // 1. 有限狀態機 (FSM) 狀態宣告
    // ==========================================
    localparam S_IDLE       = 4'd0; // 閒置狀態，等待 DMA 資料寫入
    localparam S_LOAD_A     = 4'd1; // 單多項式運算時，載入多項式 A (NTT模式)
    localparam S_LOAD_C     = 4'd2; // 載入多項式 C (INTT模式)
    localparam S_LOAD_A_PWM = 4'd3; // PWM 運算時，載入多項式 A
    localparam S_LOAD_B_PWM = 4'd4; // PWM 運算時，載入多項式 B
    localparam S_NTT_A      = 4'd5; // 執行前向 NTT 運算階段
    localparam S_PWM        = 4'd6; // 執行頻域點對點相乘階段
    localparam S_INTT_C     = 4'd7; // 執行逆向 INTT 運算階段
    localparam S_STREAM_OUT = 4'd8; // 運算結束，將 RAM 內資料透過 DMA 吐回

    reg [3:0] state, next_state;

    // ==========================================
    // 2. 計數器與定址宣告
    // ==========================================
    reg [6:0] load_cnt;   // 資料載入計數器 (0 to 127)
    reg [6:0] read_cnt;   // 運算時，記憶體讀取計數器 (0 to 127)
    reg [6:0] write_cnt;  // 運算結束，結果寫入計數器 (0 to 127)
    reg [6:0] stream_cnt; // 串流回傳計數器 (0 to 127)

    // 位元反轉定址：由於 MDC 流水線輸出的資料為位元反轉格式，寫入暫存區時需要對齊
    wire [6:0] write_cnt_br = {write_cnt[0], write_cnt[1], write_cnt[2], write_cnt[3], write_cnt[4], write_cnt[5], write_cnt[6]};

    // ==========================================
    // 3. 對稱暫存記憶體 (由 Vivado 自動推論為 LUTRAM / Distributed RAM 以減少 BRAM 浪費)
    // ==========================================
    reg [22:0] ram_a_1 [0:127]; // 多項式 A 通道 1 暫存區
    reg [22:0] ram_a_2 [0:127]; // 多項式 A 通道 2 暫存區
    reg [22:0] ram_b_1 [0:127]; // 多項式 B 通道 1 暫存區
    reg [22:0] ram_b_2 [0:127]; // 多項式 B 通道 2 暫存區
    reg [22:0] ram_c_1 [0:127]; // 多項式 C/結果 通道 1 暫存區
    reg [22:0] ram_c_2 [0:127]; // 多項式 C/結果 通道 2 暫存區

    // 核心運算時的雙通道讀取埠
    wire [22:0] ram_a_rdata1 = ram_a_1[read_cnt];
    wire [22:0] ram_a_rdata2 = ram_a_2[read_cnt];
    wire [22:0] ram_b_rdata1 = ram_b_1[read_cnt];
    wire [22:0] ram_b_rdata2 = ram_b_2[read_cnt];
    wire [22:0] ram_c_rdata1 = ram_c_1[read_cnt];
    wire [22:0] ram_c_rdata2 = ram_c_2[read_cnt];

    // ==========================================
    // 4. 加速器子模組實例化
    // ==========================================
    reg         core_en_in;
    reg  [22:0] core_x1_in, core_x2_in;

    // 前向 NTT 核心
    wire ntt_en_out;
    wire [22:0] ntt_y1_out, ntt_y2_out;
    ntt_core #(.IS_INTT(0)) u_ntt (
        .clk(aclk),
        .rst_n(aresetn),
        .en_in(core_en_in && (state == S_NTT_A)),
        .x1_in(core_x1_in),
        .x2_in(core_x2_in),
        .en_out(ntt_en_out),
        .y1_out(ntt_y1_out),
        .y2_out(ntt_y2_out)
    );

    // PWM 點對點相乘核心
    wire pwm_en_out;
    wire [22:0] pwm_y1_out, pwm_y2_out;
    pwm_core u_pwm (
        .clk(aclk),
        .rst_n(aresetn),
        .en_in(core_en_in && (state == S_PWM)),
        .polyA_y1(ram_a_rdata1),
        .polyA_y2(ram_a_rdata2),
        .polyB_y1(ram_b_rdata1),
        .polyB_y2(ram_b_rdata2),
        .en_out(pwm_en_out),
        .y1_out(pwm_y1_out),
        .y2_out(pwm_y2_out)
    );

    // 逆向 INTT 核心 (含 N^-1 後處理)
    wire intt_en_out;
    wire [22:0] intt_y1_out, intt_y2_out;
    intt_core u_intt (
        .clk(aclk),
        .rst_n(aresetn),
        .en_in(core_en_in && (state == S_INTT_C)),
        .x1_in(core_x1_in),
        .x2_in(core_x2_in),
        .en_out(intt_en_out),
        .y1_out(intt_y1_out),
        .y2_out(intt_y2_out)
    );

    // 核心運算輸入選擇多路切換器 (MUX)
    always @* begin
        core_x1_in = 23'd0;
        core_x2_in = 23'd0;
        if (state == S_NTT_A) begin
            core_x1_in = ram_a_rdata1;
            core_x2_in = ram_a_rdata2;
        end else if (state == S_INTT_C) begin
            core_x1_in = ram_c_rdata1;
            core_x2_in = ram_c_rdata2;
        end
    end

    // 計算完成後寫回暫存記憶體時的寫入定址選擇器
    wire [6:0] target_write_addr = (state == S_PWM) ? write_cnt : write_cnt_br;

    // --- 記憶體寫入埠仲裁與寫入控制 (單一寫入 Block 確保推論正確) ---
    always @(posedge aclk) begin
        if (s_axis_tvalid && s_axis_tready && (state == S_LOAD_A || state == S_LOAD_A_PWM)) begin
            ram_a_1[load_cnt] <= s_axis_tdata[22:0];
            ram_a_2[load_cnt] <= s_axis_tdata[54:32];
        end else if (ntt_en_out && state == S_NTT_A) begin
            ram_a_1[target_write_addr] <= ntt_y1_out;
            ram_a_2[target_write_addr] <= ntt_y2_out;
        end
    end

    always @(posedge aclk) begin
        if (s_axis_tvalid && s_axis_tready && state == S_LOAD_B_PWM) begin
            ram_b_1[load_cnt] <= s_axis_tdata[22:0];
            ram_b_2[load_cnt] <= s_axis_tdata[54:32];
        end
    end

    always @(posedge aclk) begin
        if (s_axis_tvalid && s_axis_tready && state == S_LOAD_C) begin
            ram_c_1[load_cnt] <= s_axis_tdata[22:0];
            ram_c_2[load_cnt] <= s_axis_tdata[54:32];
        end else if (pwm_en_out && state == S_PWM) begin
            ram_c_1[target_write_addr] <= pwm_y1_out;
            ram_c_2[target_write_addr] <= pwm_y2_out;
        end else if (intt_en_out && state == S_INTT_C) begin
            ram_c_1[target_write_addr] <= intt_y1_out;
            ram_c_2[target_write_addr] <= intt_y2_out;
        end
    end

    // ==========================================
    // 5. 狀態機狀態跳轉邏輯 (FSM Next-State Logic)
    // ==========================================
    always @* begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (s_axis_tvalid) begin
                    if (ctrl_op[1:0] == 2'b00)       next_state = S_LOAD_A;
                    else if (ctrl_op[1:0] == 2'b01)  next_state = S_LOAD_C;
                    else if (ctrl_op[1:0] == 2'b10)  next_state = S_LOAD_A_PWM;
                end
            end
            
            // 資料載入狀態跳轉
            S_LOAD_A:     if (load_cnt == 127 && s_axis_tvalid && s_axis_tready) next_state = S_NTT_A;
            S_LOAD_C:     if (load_cnt == 127 && s_axis_tvalid && s_axis_tready) next_state = S_INTT_C;
            S_LOAD_A_PWM: if (load_cnt == 127 && s_axis_tvalid && s_axis_tready) next_state = S_LOAD_B_PWM;
            S_LOAD_B_PWM: if (load_cnt == 127 && s_axis_tvalid && s_axis_tready) next_state = S_PWM;
            
            // 計算狀態跳轉
            S_NTT_A:      if (write_cnt == 127 && ntt_en_out)  next_state = S_STREAM_OUT;
            S_PWM:        if (write_cnt == 127 && pwm_en_out)  next_state = S_STREAM_OUT;
            S_INTT_C:     if (write_cnt == 127 && intt_en_out) next_state = S_STREAM_OUT;
            
            // 資料傳送回 CPU 狀態跳轉
            S_STREAM_OUT: if (stream_cnt == 127 && m_axis_tvalid && m_axis_tready) next_state = S_IDLE;
            
            default: next_state = S_IDLE;
        endcase
    end

    // ==========================================
    // 6. 狀態機時序控制邏輯 (FSM Control Logic)
    // ==========================================
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            load_cnt     <= 7'd0;
            read_cnt     <= 7'd0;
            write_cnt    <= 7'd0;
            stream_cnt   <= 7'd0;
            core_en_in   <= 1'b0;
            s_axis_tready<= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                S_IDLE: begin
                    load_cnt      <= 7'd0;
                    read_cnt      <= 7'd0;
                    write_cnt     <= 7'd0;
                    stream_cnt    <= 7'd0;
                    core_en_in    <= 1'b0;
                    if (s_axis_tvalid) begin
                        s_axis_tready <= 1'b1;
                    end else begin
                        s_axis_tready <= 1'b0;
                    end
                end
                
                // 載入資料至記憶體緩衝區
                S_LOAD_A, S_LOAD_C, S_LOAD_A_PWM, S_LOAD_B_PWM: begin
                    s_axis_tready <= 1'b1;
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (load_cnt == 127) begin
                            load_cnt      <= 7'd0;
                            s_axis_tready <= 1'b0;
                            if (state == S_LOAD_A_PWM) begin
                                core_en_in <= 1'b0;
                            end else begin
                                core_en_in <= 1'b1; // 下一週期啟動加速核心
                            end
                        end else begin
                            load_cnt <= load_cnt + 7'd1;
                        end
                    end
                end

                // 啟動加速器核心進行硬體計算
                S_NTT_A, S_PWM, S_INTT_C: begin
                    s_axis_tready <= 1'b0;
                    if (core_en_in) begin
                        if (read_cnt == 127) begin
                            core_en_in <= 1'b0;
                        end else begin
                            read_cnt <= read_cnt + 7'd1;
                        end
                    end
                    
                    if (ntt_en_out || pwm_en_out || intt_en_out) begin
                        if (write_cnt == 127) begin
                            write_cnt <= 7'd0;
                        end else begin
                            write_cnt <= write_cnt + 7'd1;
                        end
                    end
                end

                // 透過 AXI-Stream Master 將結果回傳給 AXI DMA
                S_STREAM_OUT: begin
                    s_axis_tready <= 1'b0;
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (stream_cnt == 127) begin
                            stream_cnt <= 7'd0;
                        end else begin
                            stream_cnt <= stream_cnt + 7'd1;
                        end
                    end
                end
            endcase
        end
    end

    // ==========================================
    // 7. AXI-Stream Master 輸出打包與訊號指派
    // ==========================================
    always @* begin
        m_axis_tvalid = (state == S_STREAM_OUT);
        m_axis_tlast  = (state == S_STREAM_OUT) && (stream_cnt == 127);
        
        m_axis_tdata = 64'd0;
        if (state == S_STREAM_OUT) begin
            if (ctrl_op[1:0] == 2'b00) begin
                // NTT 模式下，直接輸出 RAM A 中的頻域結果
                m_axis_tdata = {9'b0, ram_a_2[stream_cnt], 9'b0, ram_a_1[stream_cnt]};
            end else begin
                // INTT 或 PWM 模式下，輸出結果 RAM C 的時域/頻域數值
                m_axis_tdata = {9'b0, ram_c_2[stream_cnt], 9'b0, ram_c_1[stream_cnt]};
            end
        end
    end
endmodule
