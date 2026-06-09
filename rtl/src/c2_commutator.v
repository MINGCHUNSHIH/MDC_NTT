`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: c2_commutator
// 檔案名稱: c2_commutator.v
// 功能描述:
//   Radix-2 雙通道多路選擇交換器 (Commutator)。
//   是 MDC (Multi-path Delay Commutator) 流水線架構中控制資料路由的核心。
//   其運作原理為：在 Stage 使能 (en) 期間，計數器計數至定值 N。
//   在前 N 個週期，資料進行直通路由 (Straight)；後 N 個週期，通道資料交叉對調 (Cross)。
// =============================================================================

module c2_commutator #(
    parameter N = 64 // 資料交換跨度 (由 8 級 Stage 分別定義為 64, 32, 16, 8, 4, 2, 1)
)(
    input  wire        clk,   // 系統時鐘
    input  wire        rst_n, // 低電平復位
    input  wire        en,    // 路由器控制使能訊號 (對齊蝶形運算後的 3 週期延遲)
    input  wire [22:0] x1,    // 通道 1 輸入資料
    input  wire [22:0] x2,    // 通道 2 輸入資料
    output wire [22:0] y1,    // 通道 1 輸出資料
    output wire [22:0] y2     // 通道 2 輸出資料
);
    reg [($clog2(N)-1):0] count; // 路由計數器，用於計算當前 Stage 處於 Straight 還是 Cross 週期
    reg                   sel;   // 路由選擇切換旗標：0 = 直通模式 (Straight), 1 = 交叉模式 (Cross)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            sel   <= 0;
        end else if (en) begin
            if (count == N - 1) begin
                count <= 0;
                sel   <= ~sel; // 每計數滿 N 次，翻轉交換狀態
            end else begin
                count <= count + 1;
            end
        end
    end

    // 路由多路選擇邏輯
    assign y1 = (sel == 1'b0) ? x1 : x2;
    assign y2 = (sel == 1'b0) ? x2 : x1;
endmodule
