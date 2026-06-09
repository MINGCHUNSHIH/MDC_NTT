`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: butterfly_unit
// 檔案名稱: butterfly_unit.v
// 功能描述:
//   Gentleman-Sande (DIF) 蝶形運算單元。
//   主要功能是在時鐘邊緣並行執行多項式係數的加減法與旋轉因子模乘法：
//     上通道 (加法路徑): a_out = a + b mod Q
//     下通道 (減法乘法路徑): b_out = (a - b) * twiddle mod Q
//   硬體時序設計：
//     由於下通道的模乘法器 (mod_mul_3cycle) 需要耗費 3 個時鐘週期的運算延遲，
//     因此上通道的加法運算結果必須透過 3 級流水線暫存器 (a_delay_1~3) 進行延遲對齊，
//     以防止雙通道資料在輸出時產生時序偏差 (Skew)。
// =============================================================================

module butterfly_unit (
    input  wire        clk,     // 系統時鐘
    input  wire        rst_n,   // 異步低電平復位
    input  wire [22:0] a,       // 輸入係數 a (通道 1)
    input  wire [22:0] b,       // 輸入係數 b (通道 2)
    input  wire [22:0] twiddle, // 旋轉因子 (Twiddle Factor)
    output wire [22:0] a_out,   // 蝶形運算上通道輸出 (3 週期對齊)
    output wire [22:0] b_out    // 蝶形運算下通道輸出 (3 週期計算完畢)
);
    localparam signed [25:0] Q = 26'd8380417;

    reg [23:0] a_add_b;
    reg signed [24:0] a_sub_b;

    // 組合邏輯：計算單週期加法與減法並執行邊界檢測
    always @* begin
        // --- 1. 加法計算 (a + b mod Q) ---
        a_add_b = a + b;
        if (a_add_b >= Q) begin
            a_add_b = a_add_b - Q; // 超出模數時扣除 Q
        end

        // --- 2. 減法計算 (a - b mod Q) ---
        a_sub_b = $signed({1'b0, a}) - $signed({1'b0, b});
        if (a_sub_b < 0) begin
            a_sub_b = a_sub_b + Q; // 結果為負值時補上 Q
        end
    end

    // --- 3. 上通道流水線延遲對齊 (精確延遲 3 個時鐘週期) ---
    reg [22:0] a_delay_1;
    reg [22:0] a_delay_2;
    reg [22:0] a_delay_3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_delay_1 <= 0;
            a_delay_2 <= 0;
            a_delay_3 <= 0;
        end else begin
            a_delay_1 <= a_add_b[22:0];
            a_delay_2 <= a_delay_1;
            a_delay_3 <= a_delay_2;
        end
    end

    // 將延遲對齊後的上通道資料指派給輸出
    assign a_out = a_delay_3;

    // --- 4. 下通道 3 週期模數乘法器實作 ---
    mod_mul_3cycle u_mod_mul (
        .clk(clk),
        .rst_n(rst_n),
        .x(a_sub_b[22:0]),
        .y(twiddle),
        .s(b_out)
    );
endmodule
