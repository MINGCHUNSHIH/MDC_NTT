`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: ntt_stage
// 檔案名稱: ntt_stage.v
// 功能描述:
//   MDC NTT 流水線的單級運算單元 (Pipeline Stage)。
//   每一級包含了以下元件：
//     1. 旋轉因子 ROM (twiddle_rom): 提供對應 Stage 的旋轉因子。
//     2. 蝶形運算器 (butterfly_unit): 執行 Gentelman-Sande 加減模乘運算。
//     3. 延遲暫存器 (delay_unit): 延遲下通道輸出資料以利對齊。
//     4. C2 路由器狀態機 (C2 Commutator): 用來切換雙通道的路由 (Straight vs. Cross)。
//     5. 輸出暫存器 (delay_unit): 用於對齊上通道，確保時序邊界與吞吐量。
// =============================================================================

module ntt_stage #(
    parameter DELAY_N = 64, // 交換延遲跨度 (64, 32, 16, 8, 4, 2, 1)
    parameter STAGE_ID = 1, // 運算級數編號 (Stage 1 ~ 7)
    parameter IS_INTT = 0   // 運算方向 (0: 正向, 1: 逆向)
)(
    input  wire        clk,    // 系統時鐘
    input  wire        rst_n,  // 低電平復位
    input  wire        en_in,  // 輸入使能訊號
    input  wire [22:0] x1_in,  // 雙通道輸入 1
    input  wire [22:0] x2_in,  // 雙通道輸入 2
    output wire        en_out, // 輸出使能訊號
    output wire [22:0] y1_out, // 雙通道輸出 1
    output wire [22:0] y2_out  // 雙通道輸出 2
);

    wire [22:0] twiddle_w;
    wire [22:0] bu_a_out_w;
    wire [22:0] bu_b_out_w;

    // 1. 旋轉因子查表 ROM (根據 Stage 查出模乘旋轉因子)
    twiddle_rom #(.STAGE(STAGE_ID)) u_twiddle_rom (
        .clk(clk),
        .rst_n(rst_n),
        .en(en_in),
        .is_intt(IS_INTT),
        .twiddle(twiddle_w)
    );

    // 2. 實例化蝶形運算器 (BU，包含 3 週期乘法延遲)
    butterfly_unit u_bu (
        .clk(clk),
        .rst_n(rst_n),
        .a(x1_in),
        .b(x2_in),
        .twiddle(twiddle_w),
        .a_out(bu_a_out_w), 
        .b_out(bu_b_out_w)  
    );

    // 3. 底部通道（下通道）延遲單元：在 C2 路由器之前，將下通道資料延遲 DELAY_N 週期
    wire [22:0] bot_delayed_w;
    delay_unit #(.N(DELAY_N), .WIDTH(23)) u_delay_bot (
        .clk(clk),
        .rst_n(rst_n),
        .din(bu_b_out_w),
        .dout(bot_delayed_w)
    );

    // 4. 將 Stage 使能訊號延遲 3 週期以對齊蝶形運算後的 C2 控制訊號
    wire c2_start;
    delay_unit #(.N(3), .WIDTH(1)) u_delay_c2_start (
        .clk(clk),
        .rst_n(rst_n),
        .din(en_in),
        .dout(c2_start)
    );

    // --- C2 路由器控制器狀態機 ---
    // c2_cnt 計數器用來追蹤雙通道串流的資料段。
    // 在前 DELAY_N 週期中直通 (c2_sel = 0)，在後 DELAY_N 週期中交叉交換 (c2_sel = 1)。
    reg [7:0] c2_cnt; 
    reg c2_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c2_cnt <= 0;
            c2_sel <= 0;
        end else if (c2_start || c2_cnt > 0) begin
            if (c2_cnt == (DELAY_N * 2) - 1) begin
                c2_cnt <= 0;
                c2_sel <= 0; // 週期結束，復位選擇器
            end else begin
                c2_cnt <= c2_cnt + 1;
                // 當計數達到 DELAY_N 週期時，翻轉路由器通道選擇
                if (c2_cnt == DELAY_N - 1) c2_sel <= 1;
            end
        end
    end

    // 路由器 MUX 電路
    wire [22:0] c2_y1 = c2_sel ? bot_delayed_w : bu_a_out_w;
    wire [22:0] c2_y2 = c2_sel ? bu_a_out_w : bot_delayed_w;

    // 5. 左側通道（上通道）延遲單元：在 C2 路由器之後，將上通道資料延遲 DELAY_N 週期
    delay_unit #(.N(DELAY_N), .WIDTH(23)) u_delay_left (
        .clk(clk),
        .rst_n(rst_n),
        .din(c2_y1),
        .dout(y1_out)
    );

    // 右側通道無延遲直接輸出
    assign y2_out = c2_y2;

    // 6. 將級使能控制訊號 (Enable) 延遲 (3 + DELAY_N) 週期以精準對齊下一級運算
    delay_unit #(.N(3 + DELAY_N), .WIDTH(1)) u_delay_en_out (
        .clk(clk),
        .rst_n(rst_n),
        .din(en_in),
        .dout(en_out)
    );
endmodule
