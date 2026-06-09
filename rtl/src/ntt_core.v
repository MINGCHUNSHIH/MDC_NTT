`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: ntt_core
// 檔案名稱: ntt_core.v
// 功能描述:
//   前向數論轉換 (Forward NTT) 流水線計算核心。
//   為滿足 $N = 256$ 點的並行高吞吐量運算，本核心採用了 8 級串聯的 MDC 架構。
//   第一級到第七級 Stage 各包含一組 Commutator 資料對齊狀態機，
//   其跨度延遲線依序減半（64, 32, 16, 8, 4, 2, 1）。
//   第八級 Stage 無需交換，直接透過蝶形運算單元輸出結果。
// =============================================================================

module ntt_core #(
    parameter IS_INTT = 0 // 運算方向參數：0 = 前向 NTT, 1 = 逆向 INTT
)(
    input  wire        clk,    // 系統時鐘
    input  wire        rst_n,  // 低電平復位
    input  wire        en_in,  // 加速器輸入使能 (來自 DMA 控制器)
    input  wire [22:0] x1_in,  // 雙通道輸入 1
    input  wire [22:0] x2_in,  // 雙通道輸入 2
    output wire        en_out, // 運算結束使能輸出 (串接至下一級 IP)
    output wire [22:0] y1_out, // 頻域輸出 1
    output wire [22:0] y2_out  // 頻域輸出 2
);
    // 連接各級 Stage 的訊號線定義
    wire en_s1, en_s2, en_s3, en_s4, en_s5, en_s6, en_s7;
    wire [22:0] y1_s1, y1_s2, y1_s3, y1_s4, y1_s5, y1_s6, y1_s7;
    wire [22:0] y2_s1, y2_s2, y2_s3, y2_s4, y2_s5, y2_s6, y2_s7;
    wire [22:0] twiddle_s8;
    
    // --- 實例化 8 級串聯流水線 Stage ---
    // Stage 1: 延遲跨度 64 週期
    ntt_stage #(.DELAY_N(64), .STAGE_ID(1), .IS_INTT(IS_INTT)) u_stage1 (
        .clk(clk), .rst_n(rst_n), .en_in(en_in), .x1_in(x1_in), .x2_in(x2_in), .en_out(en_s1), .y1_out(y1_s1), .y2_out(y2_s1)
    );
    // Stage 2: 延遲跨度 32 週期
    ntt_stage #(.DELAY_N(32), .STAGE_ID(2), .IS_INTT(IS_INTT)) u_stage2 (
        .clk(clk), .rst_n(rst_n), .en_in(en_s1), .x1_in(y1_s1), .x2_in(y2_s1), .en_out(en_s2), .y1_out(y1_s2), .y2_out(y2_s2)
    );
    // Stage 3: 延遲跨度 16 週期
    ntt_stage #(.DELAY_N(16), .STAGE_ID(3), .IS_INTT(IS_INTT)) u_stage3 (
        .clk(clk), .rst_n(rst_n), .en_in(en_s2), .x1_in(y1_s2), .x2_in(y2_s2), .en_out(en_s3), .y1_out(y1_s3), .y2_out(y2_s3)
    );
    // Stage 4: 延遲跨度 8 週期
    ntt_stage #(.DELAY_N(8),  .STAGE_ID(4), .IS_INTT(IS_INTT)) u_stage4 (
        .clk(clk), .rst_n(rst_n), .en_in(en_s3), .x1_in(y1_s3), .x2_in(y2_s3), .en_out(en_s4), .y1_out(y1_s4), .y2_out(y2_s4)
    );
    // Stage 5: 延遲跨度 4 週期
    ntt_stage #(.DELAY_N(4),  .STAGE_ID(5), .IS_INTT(IS_INTT)) u_stage5 (
        .clk(clk), .rst_n(rst_n), .en_in(en_s4), .x1_in(y1_s4), .x2_in(y2_s4), .en_out(en_s5), .y1_out(y1_s5), .y2_out(y2_s5)
    );
    // Stage 6: 延遲跨度 2 週期
    ntt_stage #(.DELAY_N(2),  .STAGE_ID(6), .IS_INTT(IS_INTT)) u_stage6 (
        .clk(clk), .rst_n(rst_n), .en_in(en_s5), .x1_in(y1_s5), .x2_in(y2_s5), .en_out(en_s6), .y1_out(y1_s6), .y2_out(y2_s6)
    );
    // Stage 7: 延遲跨度 1 週期
    ntt_stage #(.DELAY_N(1),  .STAGE_ID(7), .IS_INTT(IS_INTT)) u_stage7 (
        .clk(clk), .rst_n(rst_n), .en_in(en_s6), .x1_in(y1_s6), .x2_in(y2_s6), .en_out(en_s7), .y1_out(y1_s7), .y2_out(y2_s7)
    );
    
    // Stage 8: 最後一級蝴蝶運算 (不包含交換路由器，僅進行純蝶形計算)
    twiddle_rom #(.STAGE(8)) u_twiddle_s8 (
        .clk(clk), .rst_n(rst_n), .en(en_s7), .is_intt(IS_INTT), .twiddle(twiddle_s8)
    );
    butterfly_unit u_stage8_bu (
        .clk(clk), .rst_n(rst_n), .a(y1_s7), .b(y2_s7), .twiddle(twiddle_s8), .a_out(y1_out), .b_out(y2_out)
    );
    
    // 將最後一級 Stage 7 的 enable 訊號延遲 3 個時鐘週期 (對齊第 8 級蝶形運算的 3 週期流水線延遲)
    delay_unit #(.N(3), .WIDTH(1)) u_delay_s8_en (
        .clk(clk), .rst_n(rst_n), .din(en_s7), .dout(en_out)
    );
endmodule
