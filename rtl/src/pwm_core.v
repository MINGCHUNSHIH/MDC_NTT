`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: pwm_core
// 檔案名稱: pwm_core.v
// 功能描述:
//   頻域點對點乘法 (Point-wise Multiplication) 運算核心。
//   當多項式經正向 NTT 轉換至頻域後，在頻域執行線性乘法。
//   為滿足雙通道並行架構，本模組實例化了兩組獨立的 3-cycle 模乘法器 (u_mul_y1, y2)，
//   並利用 3 週期延遲單元對齊輸出控制訊號 (en_out)。
// =============================================================================

module pwm_core (
    input  wire        clk,      // 系統時鐘
    input  wire        rst_n,    // 低電平復位
    input  wire        en_in,    // 運算使能輸入
    
    // 多項式 A 頻域雙通道輸入
    input  wire [22:0] polyA_y1,
    input  wire [22:0] polyA_y2,
    
    // 多項式 B 頻域雙通道輸入
    input  wire [22:0] polyB_y1,
    input  wire [22:0] polyB_y2,

    output wire        en_out,   // 運算使能輸出 (對齊 3 週期運算延遲)
    output wire [22:0] y1_out,   // 頻域相乘輸出結果 1
    output wire [22:0] y2_out    // 頻域相乘輸出結果 2
);

    // ==========================================
    // 1. 通道 1 點對點相乘 (處理 y1 分量)
    // ==========================================
    mod_mul_3cycle u_mul_y1 (
        .clk(clk),
        .rst_n(rst_n),
        .x(polyA_y1),
        .y(polyB_y1),
        .s(y1_out)
    );

    // ==========================================
    // 2. 通道 2 點對點相乘 (處理 y2 分量)
    // ==========================================
    mod_mul_3cycle u_mul_y2 (
        .clk(clk),
        .rst_n(rst_n),
        .x(polyA_y2),
        .y(polyB_y2),
        .s(y2_out)
    );

    // ==========================================
    // 3. 使能控制訊號流水線對齊 (精確延遲 3 個時鐘週期)
    // ==========================================
    delay_unit #(.N(3), .WIDTH(1)) u_delay_en (
        .clk(clk),
        .rst_n(rst_n),
        .din(en_in),
        .dout(en_out)
    );
endmodule
