# Crystals-Dilithium MDC-NTT/INTT 硬體加速器板端整合與系統驗證報告

---

## 摘要 (Abstract)
本報告呈現了一個針對 NIST 標準後量子密碼學（Post-Quantum Cryptography, PQC）數位簽章演算法 **Crystals-Dilithium** 之多項式乘法硬體加速器系統在 **Xilinx Zynq-7000 SoC (ZedBoard) FPGA** 平台上的完整實驗與驗證。本項目核心在於使用實體硬體（FPGA）重現並驗證論文中提出的數論轉換（NTT）、點對點乘法（PWM）以及逆數論轉換（INTT）演算法流程。系統利用 AXI-Stream 高速總線與 DMA 控制器將多項式係數送入加速器。實體測試結果顯示，FPGA 電路在各個階段（NTT A, NTT B, PWM, INTT）之運算數值均與論文演算法之理論黃金測資達到 **100% 完全吻合**，成功在晶片層級上實現並驗證了 Crystals-Dilithium 演算法多項式乘法之完整流程。

---

## 1. 論文演算法背景與理論流程 (Algorithm Background)

### 1.1 Crystals-Dilithium 多項式乘法理論
Crystals-Dilithium 數位簽章演算法的核心運算為商環 $R_q = \mathbb{Z}_q[x] / (x^{256} + 1)$ 上的負循環摺積（Negacyclic Convolution），其中階數 $N = 256$，模數 $q = 8380417$。

為避免 $O(N^2)$ 的高運算複雜度，論文中提出了數論轉換（NTT）的頻域相乘流程。給定時域輸入多項式 $A(x)$ 與 $B(x)$，其乘法流程定義如下：
$$\text{PolyC} = \text{INTT}(\text{NTT}(\text{PolyA}) \odot \text{NTT}(\text{PolyB}))$$
其中 $\odot$ 代表頻域係數的點對點相乘（PWM）。

### 1.2 數論轉換（NTT）與逆數論轉換（INTT）公式
* **前向數論轉換 (NTT)**：將多項式從時域轉換至頻域：
  $$\hat{a}_i = \sum_{j=0}^{N-1} a_j \zeta^j \pmod q$$
* **點對點乘法 (PWM)**：在頻域執行線性乘法：
  $$\hat{c}_i = \hat{a}_i \cdot \hat{b}_i \pmod q, \quad i \in [0, N-1]$$
* **逆數論轉換 (INTT)**：將乘積從頻域還原至時域，並乘以係數縮放因子 $N^{-1} = 8347681 \pmod q$：
  $$c_i = N^{-1} \sum_{j=0}^{N-1} \hat{c}_j \zeta^{-j} \pmod q$$

---

## 2. FPGA 硬體設計與對應電路 (FPGA Hardware Implementation)

本項目在 FPGA 上對上述演算法進行硬體對應與重現，主要包含以下電路模組與 RTL 級別硬體排程演算法：

### 2.1 雙通道流水線 MDC 架構與硬體排程演算法 (MDC Pipeline & RTL Scheduling)
為了解決時域多項式與頻域數據的並行吞吐量問題，頂層加速器核心 [ntt_core.v](file:///d:/sideproject/Dilithium_MDC_NTT_Accelerator/rtl/core/ntt_core.v) 採用了 **8 級串聯的雙通道多路延遲交換器（Multi-path Delay Commutator, MDC）流水線結構**。
每一級 Stage 包含一個蝶形運算單元（BU）、一個旋轉因子 ROM、兩個延遲暫存組以及一個交換路由器（Commutator, C2）：

1. **流水線級聯延遲規格**：
   為了滿足 256 個點的並行蝶形運算跨度，8 個運算級的數據延遲跨度分別設計為：
   * Stage 1: $DELAY\_N = 64$
   * Stage 2: $DELAY\_N = 32$
   * Stage 3: $DELAY\_N = 16$
   * Stage 4: $DELAY\_N = 8$
   * Stage 5: $DELAY\_N = 4$
   * Stage 6: $DELAY\_N = 2$
   * Stage 7: $DELAY\_N = 1$
   * Stage 8: 單純蝶形運算單元（跨度為 0）
2. **RTL 交換路由器 (C2 Commutator) 狀態機排程**：
   在每一級 Stage [ntt_stage.v](file:///d:/sideproject/Dilithium_MDC_NTT_Accelerator/rtl/core/ntt_stage.v) 中，數據的重組與對齊是透過一個二選一的交叉多路選擇器（MUX）及暫存計數器來動態排程的。當使能訊號 $en\_in$ 延遲 3 個時鐘週期（BU 的運算延遲）到達 C2 路由器時，啟動計數器 `c2_cnt`：
   * **前 $D = DELAY\_N$ 個週期**：路由選擇訊號 `c2_sel` 為 `0`。此時通道 1 輸出直通（Straight），通道 2 輸出交叉（Cross）並寫入長度為 $D$ 的延遲暫存器中。
   * **後 $D = DELAY\_N$ 個週期**：路由選擇訊號 `c2_sel` 為 `1`。此時通道 1 輸出讀取自延遲暫存器的暫存值，通道 2 直通。
   這使得原本需要大面積交換網路的資料對齊，在 RTL 中僅以一組 FIFO 與簡易計數器狀態機便能完成，達到 100% 的蝶形單元計算吞吐量。

### 2.2 蝶形運算單元 (BU) RTL 時序設計
蝶形運算單元 [butterfly_unit.v](file:///d:/sideproject/Dilithium_MDC_NTT_Accelerator/rtl/core/butterfly_unit.v) 實作 Gentleman-Sande (DIF) 蝶形演算法。在時鐘邊緣並行執行加減法與模乘法：
1. **上通道路徑 (Addition)**：計算 $a\_add\_b = a + b \pmod q$。此路徑在計算完加法後，透過三級暫存器 `a_delay_1`、`a_delay_2`、`a_delay_3` 進行 **3 個時鐘週期的流水線延遲對齊**。
2. **下通道路徑 (Subtraction & Multiplication)**：計算 $a\_sub\_b = a - b \pmod q$，隨後送入三週期延遲之模乘單元計算 $(a - b) \cdot \zeta \pmod q$。
由於兩條路徑在時序上均被約束為精確的 3 個 clock cycles 延遲，這確保了資料在高速運行時不會發生通道間的時序偏移（Skew）。

### 2.3 2-DSP 拆分與 Shift-Add Barrett 快速模數乘法演算法 (Barrett Modular Multiplier)
模乘法單元 [mod_mul_3cycle.v](file:///d:/sideproject/Dilithium_MDC_NTT_Accelerator/rtl/core/mod_mul_3cycle.v) 實現了基於 **2-DSP 運算元拆分（Operand Splitting）** 與 **Shift-Add Barrett 模數還原** 的 3 級流水線高速乘法電路：

1. **第一級時鐘週期：運算元拆分與乘法 (Operand Splitting)**：
   為了避免在 FPGA 上消耗過多大型 DSP（25x18）資源，我們將 23 位元的乘數 $y$ 進行拆分：
   $$y = y_{hi} \cdot 2^{12} + y_{lo}$$
   並藉由兩組 DSP Slices 並行計算偏乘積：
   $$p_a = x \cdot y_{hi} \quad (\text{23-bit} \times \text{11-bit} \rightarrow \text{34-bit})$$
   $$p_b = x \cdot y_{lo} \quad (\text{23-bit} \times \text{12-bit} \rightarrow \text{35-bit})$$
2. **第二級時鐘週期：Shift-Add 快速還原 (Shift-Add Reduction)**：
   利用商環模數 $q = 8380417 = 2^{23} - 2^{13} + 1$ 的特殊代數性質，我們可以將 $2^{23} \equiv 2^{13} - 1 \pmod q$ 的等價關係寫入 RTL 中。
   對於 $p_a$ 和 $p_b$，無需進行真正的求模或高位數乘法，而是利用移位加法（Shift-Add）實現模還原：
   * 計算 $r_1 \equiv p_a \cdot 2^{12} \pmod q$，其中乘 $2^{12}$ 與高位數折抵皆轉換為硬體移位。
   * 計算 $r_2 \equiv p_b \pmod q$。
3. **第三級時鐘週期：合併與邊界校正 (Merge & Final Calibration)**：
   將頻域兩個通道的估算值求和 $r_{sum} = r_1 + r_2$，並將其拆為高位元 $r_{hi}$ 與低位元 $r_{lo}$，進行最終的模還原：
   $$res\_c3 = r_{hi} \cdot 8192 - r_{hi} + r_{lo}$$
   最後以極小面積的加減法器進行邊界檢測（當值小於 0 則加上 $q$；大於等於 $q$ 則減去 $q$），輸出精確的餘數結果。此演算法完全在 3 個週期內以純移位暫存器實現，運行頻率極高。

---

## 3. 驗證方法與測試流程 (Verification Methodology & Flow)

為了嚴謹驗證實體 FPGA 晶片電路是否完全符合論文的數學模型，本項目設計了軟硬體協同驗證平台。

### 3.1 驗證方法 (Verification Methodology)
1. **軟硬體協同交叉校驗 (HW-SW Co-Verification)**：
   我們在主機端建立演算法的 Python/C 理論參照模型（Reference Model）作為黃金標準（Golden Reference）。相同的輸入多項式向量同時輸入實體 FPGA 加速器與理論參照模型，並進行係數級別的比對。
2. **內部中間狀態可觀測性 (Observability of Intermediate States)**：
   傳統的驗證僅比對最終時域結果，若中間發生運算錯誤，極易被後續運算掩蓋。本驗證方法在每個運算階段（NTT A, NTT B, PWM）完成時，利用 DMA 將 FPGA 內部的暫存器/BRAM 資料回傳至 ARM CPU，並透過 UART 印出與黃金數據逐一比對。此方法能確保每一個演算法階段的硬體行為都完全正確。

### 3.2 驗證流程 (Verification Flow)
整體的測試校驗流程分為以下五個步驟：

```text
 1. 測試向量產生 (Host PC)
    [Python 參照模型] ──產生 A, B 隨機多項式──> 導出 C 語言標頭檔 (c_arrays.h)
                                              (含 NTT_A, NTT_B, PWM, Rx 黃金測資)
                              │
                              v
 2. 硬體載入與配置 (Zynq PS7)
    [ARM CPU] ──讀入多項式──> 打包為 Split-Half 格式 ──> 設定 GPIO Mode = MODE_NTT
                              │
                              v
 3. 頻域 NTT 運算校驗 (FPGA & CPU)
    [DDR] ──DMA 傳送──> [FPGA NTT 核心] ──DMA 回傳──> [ARM CPU] ──比對 NTT_A/B_golden
                              │
                              v
 4. 頻域 PWM 運算校驗 (FPGA & CPU)
    設定 GPIO Mode = MODE_PWM
    [DDR] (NTT結果) ──DMA 傳送──> [FPGA PWM 核心] ──DMA 回傳──> [ARM CPU] ──比對 PWM_golden
                              │
                              v
 5. 時域 INTT 運算校驗 (FPGA & CPU)
    設定 GPIO Mode = MODE_INTT
    [DDR] (PWM結果) ──DMA 傳送──> [FPGA INTT 核心] ──DMA 回傳──> [ARM CPU] ──比對 Rx_golden
```

1. **第一步：生成測試向量 (Vector Generation)**：
   在電腦端執行 `generate_c_arrays.py` 產生隨機多項式 A 與 B，並利用數學公式模擬 FPGA 的內部計算順序，產出 `NTT_A_golden`、`NTT_B_golden`、`PWM_golden` 與最終 `Rx_golden` 陣列，寫入 `c_arrays.h`。
2. **第二步：ARM 載入與格式排版 (Data Packing)**：
   Zynq CPU 將多項式載入發送 Buffer，並將資料重新排列為並行雙通道規格（Split-Half Layout）。同時，透過 GPIO 寫入 `0` 設定加速器為正向 NTT 模式。
3. **第三步：驗證 NTT 階段 (NTT Stage)**：
   啟動 DMA 將多項式送入 FPGA，經數論轉換後讀回。CPU 將回傳數據與 `NTT_A_golden` 及 `NTT_B_golden` 逐一比對，驗證前向轉換電路。
4. **第四步：驗證 PWM 階段 (PWM Stage)**：
   設定 GPIO 模式為 `2` (MODE_PWM)。CPU 將頻域的 $NTT(A)$ 與 $NTT(B)$ 排版後送入 FPGA，經內部點對點 Barrett 模乘法後回傳。CPU 比對輸出與 `PWM_golden`，驗證求模乘法電路。
5. **第五步：驗證 INTT 階段與最終結果 (INTT Stage)**：
   設定 GPIO 模式為 `1` (MODE_INTT)。CPU 將頻域乘積送回 FPGA，進行逆數論轉換與 $N^{-1}$ 縮放，讀回最終時域係數，與 `Rx_golden` 進行最終校驗。

---

## 4. 實體板端系統整合與實驗平台 (System Integration & Setup)

本實驗平台建構於實體 **ZedBoard (Zynq-7000 SoC)** 開發板上，其整合目標是將論文的演算法流程透過軟硬體協作進行完整實驗。

### 4.1 系統互連拓撲 (Block Design)
本硬體加速系統在 Vivado IP Integrator 中的連接結構如下：
1. **Zynq PS7 (ARM CPU)**：執行 C 語言控制程式，負責輸入測試多項式、設定模式（NTT, PWM, INTT）以及觸發傳輸。
2. **AXI DMA 控制器**：在 ARM CPU 的 DDR 記憶體與 FPGA 加速器之間進行高速資料傳遞。
3. **Topsoft IP**：封裝了論文多項式相乘演算法的實體 FPGA 加速 IP，透過 AXI-Stream 64-bit 介面與 DMA 串接。
4. **GPIO 控制器**：控制 IP 在三個運算階段切換。

### 4.2 軟硬體資料格式對齊
* **時域輸入格式 (Split-Half Layout)**：為了匹配 FPGA 流水線的並行讀取，軟體端將 256 個係數重新打包成通道 1（前 128 個係數）與通道 2（後 128 個係數）交錯並行送入。
* **頻域輸出格式**：由於硬體管線結構，運算後的頻域係數輸出為位元反轉交錯格式。我們在實驗比對端（軟體端）對齊該格式，直接驗證 FPGA 輸出之數值與論文理論模型的正確性。

---

## 5. 演算法全流程實體測試結果 (Experimental Verification Results)

本實驗使用隨機生成的多項式 A 與 B 作為輸入，在實體 ZedBoard 開發板上依序執行了 **NTT(A) $ightarrow$ NTT(B) $ightarrow$ PWM $ightarrow$ INTT** 之完整多項式乘法演算法流程。

以下為板端 UART 串列埠回傳的實測數據與論文演算法理論黃金測資的比對紀錄（為排版簡潔，各階段皆節錄首尾數值）：

### 5.1 階段一：A 多項式正向數論轉換 NTT(A)
* **實驗目標**：驗證時域多項式 A 送入 FPGA 後，其正向數論轉換的頻域數值是否正確。
* **比對結果**：256 個頻域係數 100% 吻合論文理論值。
* **實測日誌**：
  ```text
  [HW] Computing NTT of Polynomial A...
   -> NTT(A) completed successfully.
  
  --- NTT(A) Intermediate Coefficients (256x1 Column) ---
  NTT_A[0] = 309978 (Expected: 309978)
  NTT_A[1] = 6335319 (Expected: 6335319)
  NTT_A[2] = 6021777 (Expected: 6021777)
  ...
  NTT_A[253] = 3017712 (Expected: 3017712)
  NTT_A[254] = 2691606 (Expected: 2691606)
  NTT_A[255] = 4947484 (Expected: 4947484)
  >> SUCCESS: NTT(A) verified! (All 256 coefficients match the simulation golden reference 100%)
  ```

### 5.2 階段二：B 多項式正向數論轉換 NTT(B)
* **實驗目標**：驗證時域多項式 B 送入 FPGA 後，其正向數論轉換的頻域數值是否正確。
* **比對結果**：256 個頻域係數 100% 吻合論文理論值。
* **實測日誌**：
  ```text
  [HW] Computing NTT of Polynomial B...
   -> NTT(B) completed successfully.
  
  --- NTT(B) Intermediate Coefficients (256x1 Column) ---
  NTT_B[0] = 846205 (Expected: 846205)
  NTT_B[1] = 4589693 (Expected: 4589693)
  NTT_B[2] = 230539 (Expected: 230539)
  ...
  NTT_B[253] = 4330962 (Expected: 4330962)
  NTT_B[254] = 7668474 (Expected: 7668474)
  NTT_B[255] = 7742045 (Expected: 7742045)
  >> SUCCESS: NTT(B) verified! (All 256 coefficients match the simulation golden reference 100%)
  ```

### 5.3 階段三：頻域點對點相乘 (PWM)
* **實驗目標**：驗證正向轉換後的頻域數值 $NTT(A)$ 與 $NTT(B)$，在 FPGA 內部點對點相乘及模 $q$ 還原結果是否正確。
* **比對結果**：256 個頻域乘積 100% 吻合論文理論值。
* **實測日誌**：
  ```text
  [HW] Performing Point-wise Multiplication (PWM)...
   -> PWM completed successfully.
  
  --- PWM Intermediate Coefficients (256x1 Column) ---
  PWM[0] = 6261807 (Expected: 6261807)
  PWM[1] = 5140515 (Expected: 5140515)
  PWM[2] = 4850085 (Expected: 4850085)
  ...
  PWM[253] = 470764 (Expected: 470764)
  PWM[254] = 4481179 (Expected: 4481179)
  PWM[255] = 879159 (Expected: 879159)
  >> SUCCESS: PWM verified! (All 256 coefficients match the simulation golden reference 100%)
  ```

### 5.4 階段四：逆數論轉換與最終結果 (INTT)
* **實驗目標**：驗證將頻域相乘的結果送回 FPGA 進行逆數論轉換並乘上 $N^{-1}$ 縮放後，得到的最終時域多項式係數是否正確。
* **比對結果**：時域係數 100% 正確，代表整個多項式相乘流程完全正確。
* **實測日誌**：
  ```text
  [HW] Performing INTT to obtain final product...
   -> INTT completed successfully.
  [CPU] Loading pre-simulation golden reference...
  
  --- Final Product Polynomial Coefficients (256x1 Column) ---
  Result[0] = 4196608 (Expected: 4196608)
  Result[1] = 7736592 (Expected: 7736592)
  Result[2] = 6051928 (Expected: 6051928)
  ...
  Result[253] = 7951941 (Expected: 7951941)
  Result[254] = 4114708 (Expected: 4114708)
  Result[255] = 5313240 (Expected: 5313240)
  -----------------------------------------------------------
  >> SUCCESS: Hardware full polynomial multiplication verified successfully!
  >> (All 256 coefficients match the simulation golden reference 100%)
  ```

---

## 6. 硬體資源消耗分析 (Hardware Resource Utilization)

本系統於 ZedBoard 實體晶片 **Zynq xc7z020clg484-1** 上完成了完整的綜合與佈局佈線（Synthesis & Implementation）。本節將呈現系統整體的資源消耗狀況，並進一步針對加速器核心 IP (`topsoft_0`) 進行階層式（Hierarchical）的邏輯資源消耗拆解與硬體架構優化分析。

### 6.1 DSP48E1 乘法單元資源拆解
硬體加速核心總計消耗了 **40 個 DSP48E1 Slices**，其精確的邏輯對應與數學拆解如下：

1. **單個 Barrett 模乘法器 (`mod_mul_3cycle`) 消耗：2 DSPs**
   * 為了滿足 FPGA 內部 DSP48E1 的 $25 \times 18$ 位元乘法器物理限制，我們將 23 位元的乘數 $y$ 進行拆分：$y = y_{hi} \cdot 2^{12} + y_{lo}$。
   * 第一路偏乘積 $x \cdot y_{hi}$ （23-bit $\times$ 11-bit）分配至 **1 個 DSP48E1**。
   * 第二路偏乘積 $x \cdot y_{lo}$ （23-bit $\times$ 12-bit）分配至 **1 個 DSP48E1**。
   * 兩路乘積在後續流水線階段進行移位加法（Shift-Add）整合，因而每個模乘單元固定佔用 2 個 DSP。
2. **各子模組 DSP 消耗統計**：
   * **NTT 核心 (`ntt_core.v`)：16 DSPs**
     * 256 點前向數論轉換包含 8 個運算級（Stage 1-8），雙通道 MDC 流水線結構中每級Stage配置 1 個蝶形運算單元（BU），每個 BU 內含 1 個模乘器。
     * 計算公式：$8 \text{ 個 Stage} \times 1 \text{ 個 BU/Stage} \times 2 \text{ DSPs} = 16 \text{ DSPs}$。
   * **PWM 核心 (`pwm_core.v`)：4 DSPs**
     * 頻域點對點相乘為雙通道並行設計，需要 2 個獨立的模乘法器同時對兩路輸入資料進行計算。
     * 計算公式：$2 \text{ 個獨立通道} \times 1 \text{ 個模乘器/通道} \times 2 \text{ DSPs} = 4 \text{ DSPs}$。
   * **INTT 核心 (`intt_core.v`)：20 DSPs**
     * 運算管線部分：結構與 NTT 完全對稱，包含 8 個 Stage 蝶形運算，共 8 個模乘器（16 DSPs）。
     * 輸出端縮放單元：為完成最後的 $N^{-1} = 256^{-1} \equiv 8347681 \pmod Q$ 縮放，雙通道並行輸出端各配置了 1 個獨立的乘法器（`u_post_mul_y1` 與 `u_post_mul_y2`），共 2 個模乘器（4 DSPs）。
     * 計算公式：$(8 + 2) \text{ 個模乘器} \times 2 \text{ DSPs} = 20 \text{ DSPs}$。
   * **總計**：$16 \text{ (NTT)} + 4 \text{ (PWM)} + 20 \text{ (INTT)} = 40 \text{ DSPs}$。

### 6.2 系統整體與加速器核心資源消耗對照表
以下呈現 Vivado Post-Route 實測導出的整體系統（含 Processing System, AXI DMA, Interconnect, System ILA）與加速器核心 IP (`topsoft_0`) 的資源消耗對照：

| 資源類型 (Resource Type) | 整體系統消耗 (Wrapper Total) | 加速器核心消耗 (topsoft_0) | 開發板總量 (Available) | 核心佔整體比例 (%) | 整體佔用率 (Util %) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Total LUTs** | 17,320 | **11,352** | 53,200 | 65.54 % | 32.56 % |
| &nbsp;&nbsp;&nbsp;&nbsp;*-- Logic LUTs* | 14,979 | **9,913** | 53,200 | 66.18 % | 28.16 % |
| &nbsp;&nbsp;&nbsp;&nbsp;*-- LUTRAMs* | 1,382 | **896** | 17,400 | 64.83 % | 7.94 % |
| &nbsp;&nbsp;&nbsp;&nbsp;*-- SRLs (Shift Registers)* | 959 | **543** | 17,400 | 56.62 % | 5.51 % |
| **Slice FFs (暫存器)** | 12,779 | **3,993** | 106,400 | 31.25 % | 12.01 % |
| **DSP48E1 (乘法器)** | 40 | **40** | 220 | 100.00 % | 18.18 % |
| **RAMB36E1 (36Kb BRAM)** | 6 | **0** | 140 | 0.00 % | 4.29 % |
| **RAMB18E1 (18Kb BRAM)** | 3 | **0** | 280 | 0.00 % | 1.07 % |

*註：整體系統中的 6 個 RAMB36E1 與 3 個 RAMB18E1 主要被 AXI DMA 的 FIFO 以及用於片上除錯的 System ILA (Integrated Logic Analyzer) 佔用，加速器核心本體並無消耗 Block RAM。*

### 6.3 加速器核心 IP 內部階層資源拆解 (Hierarchical Utilization Breakdown)
在 `topsoft_0` 加速器內部，各子模組的邏輯資源分佈如下表所示：

| 實例名稱 (Instance) | 對應電路模組 (Module) | Total LUTs | Logic LUTs | LUTRAMs | SRLs | FFs | DSPs |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **topsoft_0** | `design_1_topsoft_0_0` (Wrapper) | **11,352** | **9,913** | **896** | **543** | **3,993** | **40** |
| ├── **u_ntt** | `ntt_core` (前向轉換) | 4,547 | 4,276 | 0 | 271 | 1,835 | 16 |
| ├── **u_intt** | `intt_core` (逆向轉換) | 4,999 | 4,727 | 0 | 272 | 1,920 | 20 |
| ├── **u_pwm** | `pwm_core` (點對點模乘) | 753 | 753 | 0 | 0 | 153 | 4 |
| └── **(inst) / local** | `topsoft` 本體控制與緩衝區 | 1,053 | 157 | 896 | 0 | 85 | 0 |

### 6.4 硬體架構優化與資源特點分析

本系統在實作過程中針對資源配置進行了深度的架構優化，特別體現在記憶體與流水線延遲線的設計上：

1. **記憶體零 Block RAM (BRAM) 消耗設計**
   * Crystals-Dilithium 的多項式大小為 $N = 256$，每個係數為 23-bit。透過加速器的雙通道平行架構，資料被拆分為兩路，每路僅需儲存 128 個係數。
   * 對於深度僅為 128、寬度為 23-bit 的對稱暫存區（`ram_a`, `ram_b`, `ram_c`），若使用 FPGA 內部的 Block RAM（最少 18Kb 起跳），會造成極大的頻寬與容量浪費。
   * 因此，本設計在 RTL 中將其宣告為雙埠暫存器，Vivado 在綜合時會將其優化映射至 SLICEM 中的 **LUTRAM (Distributed RAM)**，共計消耗 896 個 LUTRAM 資源（使用 `RAM64M` 與 `RAM128X1D` 原語組合）。
   * 這種「零 BRAM」的設計，使得多項式存取延遲極低、佈線更加緊湊，並釋放了寶貴的片上 Block RAM 供 SoC 系統中的 DMA 與作業系統使用。
2. **基於 SRL 的極簡流水線延遲設計**
   * 在 MDC 8 級流水線中，為了滿足資料交換對齊，需要設計長度為 64, 32, 16, 8, 4, 2, 1 週期的資料延遲線。
   * 若這些移位暫存器全部以 D 觸發器（Flip-Flops, FFs）實作，光是 NTT 與 INTT 中的延遲線就需消耗：
     $$2 \text{ 通道} \times (64+32+16+8+4+2+1) \text{ 週期} \times 23\text{-bit} = 5,842 \text{ FFs}$$
   * 本設計利用 Vivado 的 **SRL (Shift Register LUT)** 推論技術，將這些固定長度的移位暫存器全部映射至 SLICEM 的 LUT 移位暫存器原語（如 `SRL16E` 或 `SRLC32E`）。這使得 `topsoft_0` 加速器本體的 FF 消耗量大幅降低至僅有 **3,993** 個，在保持 8 級雙通道全流水線的高吞吐量之餘，極大化地減少了暫存器的面積開銷。

---

## 7. 討論與結論 (Discussion & Conclusion)

1. **演算法完整實作**：本項目成功在 FPGA (ZedBoard) 上重現了 Crystals-Dilithium 多項式乘法演算法之完整數學流程（NTT A $ightarrow$ NTT B $ightarrow$ PWM $ightarrow$ INTT C）。
2. **晶片級精確吻合**：實體 FPGA 計算出的每一個時域與頻域係數，皆與理論模型（Python/C 參照模型）達到 **100% 位元級吻合**。
3. **驗證結論**：本實驗成功展示了利用雙通道 MDC 結構與 Barrett 求模電路在實體晶片上執行 Dilithium 多項式乘法之可行性，系統運作穩定且數值精確，已完全達到課堂專題展示與學術發表之規格標準。
