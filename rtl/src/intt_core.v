`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: intt_core
// 檔案名稱: intt_core.v
// 功能描述:
//   Crystals-Dilithium 逆數論轉換 (INTT) 核心運算引擎。
//   其本質結構與前向 NTT 運算對稱。本模組實例化了 `ntt_core` 並開啟參數 `IS_INTT = 1`。
//   根據 INTT 的數學定義，頻域數據還原後，必須額外乘上縮放因子 N^-1 = 256^-1 mod Q。
//   因此在 INTT 雙通道輸出端，本模組實例化了兩組後乘法器 (u_post_mul_y1, y2)，
//   以 3 週期模乘電路乘以縮放因子 8347681 (N^-1)，並相應對齊使能訊號 (en_out)。
// =============================================================================

module intt_core (
    input  wire        clk,    // 系統時鐘
    input  wire        rst_n,  // 低電平復位
    input  wire        en_in,  // 加速器啟動使能
    input  wire [22:0] x1_in,  // 雙通道輸入 1
    input  wire [22:0] x2_in,  // 雙通道輸入 2
    output wire        en_out, // 運算結束使能輸出 (對齊 3 週期後乘法延遲)
    output wire [22:0] y1_out, // 逆轉換輸出結果 1
    output wire [22:0] y2_out  // 逆轉換輸出結果 2
);
    wire ntt_en_out;
    wire [22:0] ntt_y1_out, ntt_y2_out;

    // 1. 實例化 NTT 流水線核心，並將 IS_INTT 設為 1 (啟用逆向旋轉因子)
    ntt_core #(.IS_INTT(1)) u_ntt_pipeline (
        .clk(clk),
        .rst_n(rst_n),
        .en_in(en_in),
        .x1_in(x1_in),
        .x2_in(x2_in),
        .en_out(ntt_en_out),
        .y1_out(ntt_y1_out),
        .y2_out(ntt_y2_out)
    );

    // 2. 通道 1 後乘法縮放 (乘以 N^-1 = 8347681 mod Q)
    mod_mul_3cycle u_post_mul_y1 (
        .clk(clk),
        .rst_n(rst_n),
        .x(ntt_y1_out),
        .y(23'd8347681),
        .s(y1_out)
    );

    // 3. 通道 2 後乘法縮放 (乘以 N^-1 = 8347681 mod Q)
    mod_mul_3cycle u_post_mul_y2 (
        .clk(clk),
        .rst_n(rst_n),
        .x(ntt_y2_out),
        .y(23'd8347681),
        .s(y2_out)
    );

    // 4. 將輸出使能訊號延遲 3 個時鐘週期，以匹配後乘法器 IP 的流水線延遲
    delay_unit #(.N(3), .WIDTH(1)) u_delay_en (
        .clk(clk),
        .rst_n(rst_n),
        .din(ntt_en_out),
        .dout(en_out)
    );
endmodule
