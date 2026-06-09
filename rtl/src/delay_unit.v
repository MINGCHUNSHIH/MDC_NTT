`timescale 1ns / 1ps
// =============================================================================
// 模組名稱: delay_unit
// 檔案名稱: delay_unit.v
// 功能描述:
//   可配置深度 (N) 與位元寬度 (WIDTH) 的通用資料延遲線 (Shift Register)。
//   在 MDC 流水線中用於進行前後級的蝶形資料對齊。
//   此 RTL 編寫風格經過優化，在 Vivado 中會自動推論並優化映射至 SLICEM 內的
//   SRL16E / SRLC32E (Shift Register LUTs) 邏輯單元，能大幅節省 Flip-Flops 資源。
// =============================================================================

module delay_unit #(
    parameter N     = 64, // 延遲週期數 (移位深度)
    parameter WIDTH = 23  // 資料位元寬度 (預設為多項式係數 23-bit)
) (
    input  wire             clk,   // 系統時鐘
    input  wire             rst_n, // 低電平復位
    input  wire [WIDTH-1:0] din,   // 資料輸入
    output wire [WIDTH-1:0] dout   // 資料輸出 (延遲 N 週期後)
);
    reg [WIDTH-1:0] shift_reg [0:N-1]; // 定義移位暫存陣列
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 復位時，移位暫存器清零
            for (i = 0; i < N; i = i + 1) begin
                shift_reg[i] <= 0;
            end
        end else begin
            shift_reg[0] <= din; // 第一級寫入當前輸入值
            for (i = 1; i < N; i = i + 1) begin
                shift_reg[i] <= shift_reg[i-1]; // 資料逐級位移
            end
        end
    end

    // 輸出端取出最後一級暫存器數值
    assign dout = shift_reg[N-1];
endmodule
