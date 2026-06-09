/**
 * ============================================================================
 * 專案名稱: Crystals-Dilithium 多項式乘法硬體加速器系統驗證程式
 * 平台環境: Xilinx ZedBoard (Zynq-7000 SoC, Cortex-A9 Standalone BSP)
 * 檔案名稱: main.c
 * 功能描述:
 *   本程式負責管理與控制 FPGA 上的 Crystals-Dilithium 多項式乘法加速器 IP (topsoft)。
 *   主控 CPU (Zynq PS) 透過 AXI GPIO 設定加速器模式，並利用 AXI DMA 控制器將多項式
 *   係數送入加速器核心。隨後讀回運算結果，在晶片層級驗證前向數論轉換 (NTT)、
 *   點對點相乘 (PWM) 及逆數論轉換 (INTT) 的中間級數值與最終時域乘積是否與黃金測資完全吻合。
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xgpio.h"
#include "xil_cache.h"
#include "c_arrays.h" // 包含 Python 理論參照模型預先生成的輸入多項式與各階段 Expected 黃金數值

/* 硬體元件 ID 定義 (自 xparameters.h 導入) */
#define DMA_DEV_ID      XPAR_AXIDMA_0_DEVICE_ID
#define GPIO_DEV_ID     XPAR_GPIO_0_DEVICE_ID
#define DATA_LENGTH     256
#define BYTES_TO_TX     (DATA_LENGTH * sizeof(uint32_t)) // 每次傳輸係數的位元組數 (1024 Bytes)

/* 加速器控制模式定義 (GPIO 控制指令) */
#define MODE_NTT        0  // 前向數論轉換模式 (Forward NTT)
#define MODE_INTT       1  // 逆數論轉換模式 (INTT, 內含 N^-1 縮放)
#define MODE_PWM        2  // 頻域點對點相乘模式 (Point-Wise Multiplication)

/* Crystals-Dilithium 商環模數 */
#define Q 8380417

/* 實體 IP 驅動結構體 */
XAxiDma AxiDma;
XGpio Gpio;

/* DMA 專用緩衝區 (必須向 32 位元組對齊以符合 Cache Line 大小，避免快取不一致問題) */
uint32_t TxBufferPtr[512] __attribute__((aligned(32)));
uint32_t RxBufferPtr[DATA_LENGTH] __attribute__((aligned(32)));
uint32_t A_freq_buffer[DATA_LENGTH] __attribute__((aligned(32)));
uint32_t B_freq_buffer[DATA_LENGTH] __attribute__((aligned(32)));
uint32_t C_freq_buffer[DATA_LENGTH] __attribute__((aligned(32)));

/* CPU 時域輸入緩衝區與 Golden 參考緩衝區 */
uint32_t PolyA[DATA_LENGTH];
uint32_t PolyB[DATA_LENGTH];
uint32_t C_golden[DATA_LENGTH];

/**
 * 函數名稱: print_dma_status
 * 功能描述: 讀取並列印 AXI DMA 內部的狀態暫存器 (Status Register)，用於硬體除錯。
 */
void print_dma_status() {
    u32 tx_sr = XAxiDma_ReadReg(AxiDma.RegBase, 0x04); // MM2S DMA Status Register
    u32 rx_sr = XAxiDma_ReadReg(AxiDma.RegBase, 0x34); // S2MM DMA Status Register
    printf("[DMA Status] TX (MM2S) SR: 0x%08X, RX (S2MM) SR: 0x%08X\r\n", (unsigned int)tx_sr, (unsigned int)rx_sr);
}

/**
 * 函數名稱: init_hardware
 * 功能描述: 初始化 AXI GPIO 控制器與 AXI DMA 控制器，配置傳輸方向並關閉中斷改採輪詢。
 * 傳回值: XST_SUCCESS 代表初始化成功，其他代表失敗。
 */
int init_hardware() {
    int Status;
    
    // 1. 初始化 AXI GPIO 控制器
    Status = XGpio_Initialize(&Gpio, GPIO_DEV_ID);
    if (Status != XST_SUCCESS) {
        printf("GPIO Initialization Failed\r\n");
        return XST_FAILURE;
    }
    // 設定 GPIO 通道 1 為全輸出模式 (控制加速器模式選取)
    XGpio_SetDataDirection(&Gpio, 1, 0x0);

    // 2. 初始化 AXI DMA 控制器
    XAxiDma_Config *CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (!CfgPtr) {
        printf("No config found for %d\r\n", DMA_DEV_ID);
        return XST_FAILURE;
    }
    Status = XAxiDma_CfgInitialize(&AxiDma, CfgPtr);
    if (Status != XST_SUCCESS) {
        printf("Initialization failed %d\r\n", Status);
        return XST_FAILURE;
    }
    
    // 3. 關閉 DMA 中斷功能 (採用 Simple Transfer Polling 模式進行資料傳輸)
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    return XST_SUCCESS;
}

/**
 * 函數名稱: schoolbook_poly_mul
 * 功能描述: 經典直式多項式乘法 (Schoolbook Multiplication)，計算商環 R_q = Z_q[x]/(x^256+1) 下的負循環摺積。
 *           用於 CPU 軟體端驗證。
 */
void schoolbook_poly_mul(uint32_t *a, uint32_t *b, uint32_t *c) {
    uint64_t temp[512] = {0};
    // 1. 執行 256x256 的大數乘加運算
    for (int i = 0; i < 256; i++) {
        for (int j = 0; j < 256; j++) {
            temp[i + j] = (temp[i + j] + (uint64_t)a[i] * b[j]) % Q;
        }
    }
    // 2. 應用負循環商環關係 x^256 = -1 (即 c_i = temp_i - temp_{i+256} mod Q)
    for (int i = 0; i < 256; i++) {
        uint64_t val1 = temp[i];
        uint64_t val2 = temp[i + 256];
        if (val1 >= val2) {
            c[i] = (val1 - val2) % Q;
        } else {
            c[i] = (val1 + Q - val2) % Q;
        }
    }
}

/**
 * 函數名稱: bit_reverse_c
 * 功能描述: 執行輸入值的位元反轉 (Bit Reversal) 運算。
 */
uint32_t bit_reverse_c(uint32_t val, int bits) {
    uint32_t res = 0;
    for (int i = 0; i < bits; i++) {
        if ((val >> i) & 1) {
            res |= (1 << (bits - 1 - i));
        }
    }
    return res;
}

/**
 * 函數名稱: run_dma_transfer
 * 功能描述: 設定硬體模式，對齊快取記憶體，並呼叫 DMA 進行非阻塞傳輸後輪詢至傳輸完畢。
 * 參數說明:
 *   mode: 加速器運算模式 (MODE_NTT, MODE_PWM, MODE_INTT)
 *   tx_addr: CPU 發送緩衝區記憶體實體位址
 *   tx_size: 發送位元組大小
 *   rx_addr: CPU 接收緩衝區記憶體實體位址
 *   rx_size: 接收位元組大小
 */
int run_dma_transfer(u32 mode, void *tx_addr, int tx_size, void *rx_addr, int rx_size) {
    // 1. 透過 GPIO 寫入模式選擇訊號至加速器 FSM 暫存器
    XGpio_DiscreteWrite(&Gpio, 1, mode);

    // 2. 快取寫回與清空 (Flush Cache)：將 CPU 記憶體中修改過的資料同步寫回實體 DDR 中，避免 DMA 讀取到舊值
    Xil_DCacheFlushRange((UINTPTR)tx_addr, tx_size);
    Xil_DCacheFlushRange((UINTPTR)rx_addr, rx_size);

    // 3. 啟動 DMA S2MM (裝置到 CPU 記憶體) 傳輸通道
    int status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)rx_addr, rx_size, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        printf("DMA RX SimpleTransfer Failed: %d\r\n", status);
        return -1;
    }

    // 4. 啟動 DMA MM2S (CPU 記憶體到裝置) 傳輸通道，觸發硬體加速 IP 開始運作
    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)tx_addr, tx_size, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) {
        printf("DMA TX SimpleTransfer Failed: %d\r\n", status);
        return -1;
    }

    // 5. 輪詢等待 DMA 發送完畢，並包含超時安全機制
    int timeout = 0;
    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE)) {
        timeout++;
        if (timeout > 20000000) {
            printf("[TIMEOUT] DMA TX hung! Mode: %lu\r\n", (unsigned long)mode);
            print_dma_status();
            return -1;
        }
    }

    // 6. 輪詢等待 DMA 接收完畢，確保資料已從 FPGA 傳送回實體 DDR 中
    timeout = 0;
    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA)) {
        timeout++;
        if (timeout > 20000000) {
            printf("[TIMEOUT] DMA RX hung! Mode: %lu\r\n", (unsigned long)mode);
            print_dma_status();
            return -1;
        }
    }

    // 7. 快取無效化 (Invalidate Cache)：使 CPU 當前對應記憶體區間的 L1/L2 快取失效，強迫 CPU 下次讀取必須直接存取由 DMA 寫入的最新實體 DDR 資料
    Xil_DCacheInvalidateRange((UINTPTR)rx_addr, rx_size);
    return 0;
}

/**
 * 函數名稱: main
 * 功能描述: 系統主程式。執行軟硬體協同驗證的核心控制。
 */
int main() {
    // 為了防止主機端 serial port 尚未連接完成，進行大約 5 秒的純軟體忙碌等待延遲
    volatile uint32_t delay_cnt;
    for (delay_cnt = 0; delay_cnt < 800000000; delay_cnt++) {
        // busy wait
    }
    printf("\r\n===================================================\r\n");
    printf("--- Crystals-Dilithium Full Poly Mul Hardware Verification ---\r\n");
    printf("===================================================\r\n");

    // 初始化硬體驅動
    if (init_hardware() != XST_SUCCESS) {
        return -1;
    }

    // 1. 將預先載入的 Golden 測資填入 CPU 控制緩衝區
    for (int i = 0; i < DATA_LENGTH; i++) {
        PolyA[i] = PolyA_golden[i];
        PolyB[i] = PolyB_golden[i];
    }
    printf("[CPU] Generated random Polynomials A & B.\r\n");

    // 2. 執行並驗證第一階段：多項式 A 的正向數論轉換 NTT(A)
    printf("[HW] Computing NTT of Polynomial A...\r\n");
    // 將輸入資料重新排序成雙通道分流佈局 (Split-Half Layout) 送入 DMA 發送緩衝區
    for (int t = 0; t < 128; t++) {
        TxBufferPtr[2 * t] = PolyA[t];
        TxBufferPtr[2 * t + 1] = PolyA[t + 128];
    }
    if (run_dma_transfer(MODE_NTT, TxBufferPtr, 1024, A_freq_buffer, 1024) != 0) {
        return -1;
    }
    printf(" -> NTT(A) completed successfully.\r\n");

    // 列印與比對結果
    printf("\r\n--- NTT(A) Intermediate Coefficients (256x1 Column) ---\r\n");
    int ntt_a_success = 1;
    for (int i = 0; i < DATA_LENGTH; i++) {
        printf("NTT_A[%d] = %lu (Expected: %lu)\r\n", i, (unsigned long)A_freq_buffer[i], (unsigned long)NTT_A_golden[i]);
        if (A_freq_buffer[i] != NTT_A_golden[i]) {
            ntt_a_success = 0;
        }
    }
    if (ntt_a_success) {
        printf(">> SUCCESS: NTT(A) verified! (All 256 coefficients match the simulation golden reference 100%%)\r\n\r\n");
    } else {
        printf(">> FAILED: NTT(A) mismatch detected!\r\n\r\n");
    }

    // 3. 執行並驗證第二階段：多項式 B 的正向數論轉換 NTT(B)
    printf("[HW] Computing NTT of Polynomial B...\r\n");
    for (int t = 0; t < 128; t++) {
        TxBufferPtr[2 * t] = PolyB[t];
        TxBufferPtr[2 * t + 1] = PolyB[t + 128];
    }
    if (run_dma_transfer(MODE_NTT, TxBufferPtr, 1024, B_freq_buffer, 1024) != 0) {
        return -1;
    }
    printf(" -> NTT(B) completed successfully.\r\n");

    printf("\r\n--- NTT(B) Intermediate Coefficients (256x1 Column) ---\r\n");
    int ntt_b_success = 1;
    for (int i = 0; i < DATA_LENGTH; i++) {
        printf("NTT_B[%d] = %lu (Expected: %lu)\r\n", i, (unsigned long)B_freq_buffer[i], (unsigned long)NTT_B_golden[i]);
        if (B_freq_buffer[i] != NTT_B_golden[i]) {
            ntt_b_success = 0;
        }
    }
    if (ntt_b_success) {
        printf(">> SUCCESS: NTT(B) verified! (All 256 coefficients match the simulation golden reference 100%%)\r\n\r\n");
    } else {
        printf(">> FAILED: NTT(B) mismatch detected!\r\n\r\n");
    }

    // 4. 執行並驗證第三階段：點對點乘法 (PWM)
    printf("[HW] Performing Point-wise Multiplication (PWM)...\r\n");
    // 將計算好的頻域 A_freq 與 B_freq 資料打包合併傳入發送暫存區
    for (int i = 0; i < DATA_LENGTH; i++) {
        TxBufferPtr[i] = A_freq_buffer[i];
        TxBufferPtr[i + 256] = B_freq_buffer[i];
    }
    if (run_dma_transfer(MODE_PWM, TxBufferPtr, 2048, C_freq_buffer, 1024) != 0) {
        return -1;
    }
    printf(" -> PWM completed successfully.\r\n");

    printf("\r\n--- PWM Intermediate Coefficients (256x1 Column) ---\r\n");
    int pwm_success = 1;
    for (int i = 0; i < DATA_LENGTH; i++) {
        printf("PWM[%d] = %lu (Expected: %lu)\r\n", i, (unsigned long)C_freq_buffer[i], (unsigned long)PWM_golden[i]);
        if (C_freq_buffer[i] != PWM_golden[i]) {
            pwm_success = 0;
        }
    }
    if (pwm_success) {
        printf(">> SUCCESS: PWM verified! (All 256 coefficients match the simulation golden reference 100%%)\r\n\r\n");
    } else {
        printf(">> FAILED: PWM mismatch detected!\r\n\r\n");
    }

    // 5. 執行並驗證第四階段：逆數論轉換與最終結果 (INTT)
    printf("[HW] Performing INTT to obtain final product...\r\n");
    for (int i = 0; i < DATA_LENGTH; i++) {
        TxBufferPtr[i] = C_freq_buffer[i];
    }
    if (run_dma_transfer(MODE_INTT, TxBufferPtr, 1024, RxBufferPtr, 1024) != 0) {
        return -1;
    }
    printf(" -> INTT completed successfully.\r\n");

    printf("[CPU] Loading pre-simulation golden reference...\r\n");

    // 6. 印出最終乘積多項式係數並與理論預期的 Golden 陣列做精確比對
    printf("\r\n--- Final Product Polynomial Coefficients (256x1 Column) ---\r\n");
    int success = 1;
    for (int i = 0; i < DATA_LENGTH; i++) {
        printf("Result[%d] = %lu (Expected: %lu)\r\n", i, (unsigned long)RxBufferPtr[i], (unsigned long)Rx_golden[i]);
        if (RxBufferPtr[i] != Rx_golden[i]) {
            success = 0;
        }
    }
    printf("-----------------------------------------------------------\r\n");

    if (success) {
        printf(">> SUCCESS: Hardware full polynomial multiplication verified successfully!\r\n");
        printf(">> (All 256 coefficients match the simulation golden reference 100%%)\r\n");
    } else {
        printf(">> FAILED: Mismatch detected between Hardware and Software reference!\r\n");
    }

    return 0;
}
