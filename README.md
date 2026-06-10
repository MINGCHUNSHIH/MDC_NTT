# Crystals-Dilithium MDC-NTT 多項式相乘硬體加速器 IP 倉庫 (MDC-NTT Accelerator IP Repository)

本專案為針對 NIST 後量子密碼學（PQC）標準數位簽章演算法 **Crystals-Dilithium** 之多項式相乘硬體加速器 IP 倉庫。項目完整實現了 8 級雙通道 MDC-NTT/INTT 流水線，並在 **Xilinx Zynq-7000 SoC (ZedBoard) 開發板**上完成實體晶片驗證，中間級數值與最終時域乘積與理論數學模型達到 **100% 位元級精確吻合**。

---

## 📂 專案目錄結構 (Repository Structure)

```text
├── report/
│   └── Dilithium_Accelerator_Verification_Report.md  # 完整的硬體架構設計與系統驗證報告
├── rtl/
│   ├── component.xml                                 # Vivado IP 描述檔 (topsoft_v1_0)
│   ├── xgui/                                         # IP 的自定義 GUI 檔案
│   └── src/                                          # 自定義 AXI-Stream 加速核心 Verilog 程式碼
│       ├── poly_multiplier_top.v                     # 支援 RTL 前仿真 (Pre-simulation) 的頂層測試核心
│       ├── topsoft.v                                 # 適用於 SoC Block Design 的頂層 AXI-Stream 包裝 IP 模組
│       ├── ntt_core.v                                # 前向 NTT 計算引擎
│       ├── intt_core.v                               # 逆向 INTT 計算引擎 (含 N^-1 縮放)
│       ├── pwm_core.v                                # 頻域點對點相乘核心
│       ├── mod_mul_3cycle.v                          # 3-Cycle Barrett 模乘法器 (2-DSP 拆分)
│       ├── butterfly_unit.v                          # Gentleman-Sande (DIF) 蝶形運算單元
│       ├── c2_commutator.v                           # MDC 流水線交換路由器
│       ├── delay_unit.v                              # 移位延遲暫存組
│       └── *.mem / *.sv                              # 仿真記憶體初始化檔案與前仿真 Testbench (tb_poly_multiplier_top.sv)
└── src/
    └── main.c                                        # Zynq ARM PS 端 C 語言驅動與系統驗證程式
```

---

## 🛠️ 開發環境需求 (Requirements)
* **Xilinx Vivado Design Suite 2019.1** (或相容版本)
* **硬體平台**: Avnet ZedBoard (xc7z020clg484-1)

---

## 💻 RTL 前仿真驗證 (Pre-simulation)

本專案提供了完整的行為級前仿真平台，可用於驗證 Verilog RTL 的數學正確性：

1. 在 Vivado 中開啟或新增一個模擬專案，並將 `rtl/src/` 下的所有 `.v`、`.sv` 與 `.mem` 檔案加入專案。
2. 將 `tb_poly_multiplier_top.sv` 設定為模擬頂層 (Simulation Top)。
3. 執行前仿真 (Behavioral Simulation)，模擬會自動讀取 `.mem` 測資並逐一驗證以下四個關鍵階段的數值：
   * **Check Point 1**: NTT(A) 係數比對
   * **Check Point 2**: NTT(B) 係數比對
   * **Check Point 3**: PWM (點對點相乘) 比對
   * **Check Point 4**: INTT(C) 最終時域係數比對
   若所有階段計算皆與理論黃金參考一致，模擬控制台會印出 `>> INTT_C PASS! 全線通關！` 並結束。

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
