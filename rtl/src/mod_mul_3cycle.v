`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: mod_mul_3cycle
// 檔案名稱: mod_mul_3cycle.v
// 功能描述:
//   Crystals-Dilithium 商環 (模數 Q = 8380417) 下的 3 級流水線高速模乘法器。
//   硬體設計上利用 2-DSP 運算元拆分技術與基於 Shift-Add 的 Barrett 快速模還原演算法，
//   在不需要使用除法器、大面積取模器以及大型 (25x18以上) 乘法器的情況下，在 3 個 Clock 內完成求模乘法。
//
// 輸入:  x (23-bit), y (23-bit)
// 輸出:  s = x * y mod Q (23-bit)
// =============================================================================

module mod_mul_3cycle (
    input  wire        clk,   // 系統時鐘
    input  wire        rst_n, // 異步低電平復位訊號
    input  wire [22:0] x,     // 23 位元乘數 x
    input  wire [22:0] y,     // 23 位元被乘數 y
    output reg  [22:0] s      // 23 位元計算餘數結果 s
);
    // Dilithium 模數 Q = 8380417 = 2^23 - 2^13 + 1
    localparam [23:0] Q = 24'd8380417;

    // ── Pipeline Cycle 1 ──
    // 運算元拆分技術：將 23-bit 乘數 y 拆解成高 11 位元與低 12 位元：
    // y = y_hi * 2^12 + y_lo
    // 這使得計算偏乘積時，可以用 23x11 與 23x12 乘法，完美對應並映射至 FPGA 內部的 DSP48E1 乘法 Slices。
    reg [33:0] p_a; // 儲存偏乘積 p_a = x * y_hi (23-bit * 11-bit -> 34-bit)
    reg [34:0] p_b; // 儲存偏乘積 p_b = x * y_lo (23-bit * 12-bit -> 35-bit)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_a <= 0;
            p_b <= 0;
        end else begin
            p_a <= x * y[22:12]; // 高位偏乘積計算
            p_b <= x * y[11:0];  // 低位偏乘積計算
        end
    end

    // ── Pipeline Cycle 2 ──
    // Shift-Add Barrett 快速還原：
    // 利用代數關係 2^23 = 2^13 - 1 mod Q。
    // 這代表當數值需要乘上 2^23 時，在硬體上只要進行 2^13 移位與減法即可，不需實質大數取模。
    // 將 p_a 與 p_b 對應的位元分段取出，利用純移位加法進行局部模還原：
    reg signed [25:0] r1; // 通道 1 局部模還原結果
    reg signed [25:0] r2; // 通道 2 局部模還原結果

    // p_a 分段定義
    wire [2:0]  pa_33_31 = p_a[33:31];
    wire [9:0]  pa_30_21 = p_a[30:21];
    wire [9:0]  pa_20_11 = p_a[20:11];
    wire [12:0] pa_33_21 = p_a[33:21];
    wire [22:0] pa_33_11 = p_a[33:11];
    wire [10:0] pa_10_0  = p_a[10:0];

    // p_b 分段定義
    wire [1:0]  pb_34_33 = p_b[34:33];
    wire [9:0]  pb_32_23 = p_b[32:23];
    wire [11:0] pb_34_23 = p_b[34:23];
    wire [22:0] pb_22_0  = p_b[22:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1 <= 0;
            r2 <= 0;
        end else begin
            // 透過移位乘以 8192 (2^13) 與 4096 (2^12) 進行硬體極速代換
            r1 <= 8192 * ($signed({1'b0, pa_33_31}) + $signed({1'b0, pa_30_21}) + $signed({1'b0, pa_20_11}))
                  - ($signed({1'b0, pa_33_31}) + $signed({1'b0, pa_33_21}) + $signed({1'b0, pa_33_11}))
                  + ($signed({1'b0, pa_10_0}) * 4096);
            r2 <= ($signed({1'b0, pb_34_33}) + $signed({1'b0, pb_32_23})) * 8192
                  - ($signed({1'b0, pb_34_33}) + $signed({1'b0, pb_34_23}))
                  + $signed({1'b0, pb_22_0});
        end
    end

    // ── Pipeline Cycle 3 ──
    // 合併通道與邊界校正：
    // 將局部還原結果 r1 與 r2 相加得到 r_sum，並對高位數進行最終摺疊與邊界檢測。
    wire signed [26:0] r_sum = r1 + r2;
    wire signed [4:0]  r_hi  = r_sum >>> 23; // 取出高位除數
    wire [22:0]        r_lo  = r_sum[22:0];  // 取出低位餘數

    reg signed [24:0] res_c3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s <= 0;
        end else begin
            // 最終模還原摺疊：res_c3 = r_hi * 8192 - r_hi + r_lo
            res_c3 = r_hi * 8192 - r_hi + $signed({1'b0, r_lo});
            // 邊界校正：由於結果可能落在 [-Q, 2Q] 區間，使用簡易的加減法器進行溢位檢測與約束
            if (res_c3 < 0) begin
                s <= res_c3 + $signed({1'b0, Q}); // 負值時補上模數 Q
            end else if (res_c3 >= Q) begin
                s <= res_c3 - $signed({1'b0, Q}); // 大於模數時扣除 Q
            end else begin
                s <= res_c3[22:0];                 // 合法範圍直接輸出
            end
        end
    end
endmodule
