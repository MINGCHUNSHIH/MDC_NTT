# Crystals-Dilithium MDC-NTT 多項式相乘硬體加速器釋出套件 (MDC-NTT Accelerator Release)

本專案為針對 NIST 後量子密碼學（PQC）標準數位簽章演算法 **Crystals-Dilithium** 之多項式相乘硬體加速器。項目完整實現了 8 級雙通道 MDC-NTT/INTT 流水線，並在 **Xilinx Zynq-7000 SoC (ZedBoard) 開發板**上完成實體晶片驗證，中間級數值與最終時域乘積與理論數學模型達到 **100% 位元級精確吻合**。

---

## 📂 專案目錄結構 (Repository Structure)

```text
├── report/
│   └── Dilithium_Accelerator_Verification_Report.md  # 完整的硬體架構設計與系統驗證報告
├── rtl/
│   ├── component.xml                                 # Vivado IP 描述檔 (topsoft_v1_0)
│   ├── xgui/                                         # IP 的自定義 GUI 檔案
│   └── src/                                          # 自定義 AXI-Stream 加速核心 Verilog 程式碼
│       ├── topsoft.v                                 # 頂層 AXI-Stream 包裝 IP 模組 (FSM + LUTRAM)
│       ├── ntt_core.v                                # 前向 NTT 計算引擎
│       ├── intt_core.v                               # 逆向 INTT 計算引擎 (含 N^-1 縮放)
│       ├── pwm_core.v                                # 頻域點對點相乘核心
│       ├── mod_mul_3cycle.v                          # 3-Cycle Barrett 模乘法器 (2-DSP 拆分)
│       ├── butterfly_unit.v                          # Gentleman-Sande (DIF) 蝶形運算單元
│       ├── c2_commutator.v                           # MDC 流水線交換路由器
│       ├── delay_unit.v                              # 移位延遲暫存組
│       └── *.mem / *.sv                              # 模擬記憶體初始化檔案與測試平台
├── src/
│   └── main.c                                        # Zynq ARM PS 端 C 語言驅動與系統驗證程式
├── tcl/
│   ├── rebuild_project_from_scratch.tcl              # 從零重建 Vivado 專案與編譯 Bitstream 的主腳本
│   ├── design_1.tcl                                  # Block Design 連線腳本 (自動拉線)
│   ├── rebuild.tcl                                   # 同步最新程式碼並重編譯現有專案的腳本
│   └── run_program.tcl                               # XSCT 自動化燒錄、下載與板端執行腳本
└── .gitignore                                        # 排除 Vivado 編譯與日誌快取檔案
```

---

## 🛠️ 開發環境需求 (Requirements)
* **Xilinx Vivado Design Suite 2019.1** (或相容版本)
* **Xilinx SDK / XSCT 2019.1**
* **硬體平台**: Avnet ZedBoard (xc7z020clg484-1)

---

## 🚀 一鍵重建專案與編譯 (Rebuild from Scratch)

本專案提供全自動化的重建腳本，能在不遺失任何 IP 配置與連線的前提下，直接從零重現完整的 Block Design 設計：

1. 開啟 Vivado Tcl Shell（或在 Windows CMD 中定位至 `tcl/` 目錄）。
2. 執行以下命令啟動專案一鍵重建：
   ```bash
   vivado -mode batch -source rebuild_project_from_scratch.tcl
   ```
   **腳本將自動執行**：
   * 建立全新 Vivado 專案（目標開發板為 ZedBoard）。
   * 將本地 `rtl/` 資料夾註冊為 IP 倉庫，載入 `topsoft_v1_0` 加速器 IP。
   * 執行 `design_1.tcl` 自動生成 Zynq PS、AXI DMA、GPIO、AXI SmartConnect 的 Block Design，並**自動完成全部內部連線**。
   * 自動產生頂層 HDL Wrapper。
   * 啟動綜合與實作（Synthesis & Implementation），自動生成用於實體板端燒錄的二進制位元流檔案 **`design_1_wrapper.bit`**。

---

## 🎯 實體板端自動化燒錄與執行 (XSCT Execution)

當 Vivado 成功生成 Bitstream 且您已將 ZedBoard 連接至本機後，您可以使用 XSCT 腳本進行一鍵自動化燒錄與執行：

1. 開啟 Xilinx Software Command-line Tool (XSCT) 終端機。
2. 切換至 `tcl/` 目錄，執行：
   ```bash
   xsct run_program.tcl
   ```
   **腳本將自動執行**：
   * 指定與更新 SDK 工作區與硬體平台規格檔 (`.hdf`)。
   * 自動編譯 C 驅動程式專案 (`main.c`) 與 BSP 檔。
   * 通過 JTAG 對 ZedBoard 進行系統重置與 PL 端 Bitstream 燒錄。
   * 載入處理器系統配置 (`ps7_init.tcl`)。
   * 將編譯完成的 ELF 載入至 ARM 處理器 Cortex-A9 Core 0 並啟動運行。
3. 您可以開啟任何 Serial Terminal（如 PuTTY, Xshell），連接至 ZedBoard 對應的 COM 埠（Baud Rate: `115200`），即可看到如下的硬體加速全流程（NTT A $\rightarrow$ NTT B $\rightarrow$ PWM $\rightarrow$ INTT C）逐點比對與 100% 成功吻合的實測日誌！

---

## 📊 硬體資源消耗摘要 (Post-Route Resource)

加速核心 `topsoft` 總共消耗 **40 個 DSP48E1 Slices**（Barrett 模乘法器每組佔用 2 DSP，NTT 佔用 16 DSP，PWM 佔用 4 DSP，INTT 佔用 20 DSP）。
記憶體部分經過 RTL 宣告優化，**完全不消耗 BRAM**，全數映射至高頻寬、低延遲的 **LUTRAM** 與 **SRLs** 移位暫存器中：

| 資源類型 | 加速器核心消耗 (topsoft_0) | 開發板總量 (Available) | 佔用率 (%) |
| :--- | :---: | :---: | :---: |
| **Logic LUTs** | **9,913** | 53,200 | 18.63 % |
| **LUTRAMs** | **896** | 17,400 | 5.15 % |
| **SRLs (Shift Registers)** | **543** | 17,400 | 3.12 % |
| **Slice FFs (暫存器)** | **3,993** | 106,400 | 3.75 % |
| **DSP48E1 (乘法器)** | **40** | 220 | 18.18 % |
| **BRAMs (Block RAM)** | **0** | 140 | 0.00 % |

*詳細的架構分析與模擬歷程，請參見 [Dilithium_Accelerator_Verification_Report.md](report/Dilithium_Accelerator_Verification_Report.md)。*
