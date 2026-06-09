# =============================================================================
# XSCT 自動化硬體燒錄與應用程式下載運行 Tcl 腳本 (run_program.tcl)
# 適用環境: Xilinx Software Command-line Tool (XSCT) / SDK 2019.1
# 功能描述:
#   1. 指定 SDK 工作區 (Workspace)。
#   2. 更新 SDK 的硬體規格平台 (.hdf)，重新同步暫存器定義。
#   3. 編譯 C 語言的 Board Support Package (BSP) 與測試應用專案。
#   4. 通過 JTAG 連接 ZedBoard，對 APU (Dual Cortex-A9) 進行系統重置以解除匯流排鎖死。
#   5. 燒錄編編譯好的 .bit 二進制檔至 PL 端 FPGA。
#   6. 啟動 PS 端系統初始化 (ps7_init) 配置實體 DDR 暫存器。
#   7. 下載 ELF 二進制檔至 ARM Core 0 並啟動運行，完成實體板端驗證。
# =============================================================================

# 1. 指定工作區
setws D:/sideproject/soc/final/final.sdk

# 2. 同步並更新硬體平台規格
puts "\[XSCT\] 正在更新硬體規格定義..."
updatehw -hw design_1_wrapper_hw_platform_0 -newhwspec D:/sideproject/soc/final/final.sdk/design_1_wrapper.hdf

# 3. 自動重建 BSP 與 應用程式專案
puts "\[XSCT\] 正在編譯 BSP 專案..."
projects -build -type bsp -name ntt_test_bsp
puts "\[XSCT\] 正在編譯 C 測試應用專案..."
projects -build -type app -name ntt_test

# 4. 連接至 JTAG 模擬器
puts "\[XSCT\] 正在連接 JTAG 控制目標..."
connect

# 5. 重置系統 (防止先前執行導致 AXI 匯流排鎖死)
puts "\[XSCT\] 正在執行系統復位..."
catch {
    targets -set -nocase -filter {name =~"APU*"} -index 0
    rst -system
    puts "\[XSCT\] 已成功通過 APU 核心進行系統復位。"
} msg1
catch {
    targets -set -filter {name =~ "xc7z020"} -index 0
    rst -system
    puts "\[XSCT\] 已成功通過 xc7z020 晶片進行系統復位。"
} msg2
puts "\[XSCT\] 復位狀態報告: APU: $msg1 | FPGA: $msg2"
after 3000

# 6. 配置 FPGA (燒錄 PL 端電路設計 Bitstream)
puts "\[XSCT\] 正在將 Bitstream 燒錄至 FPGA PL 端..."
targets -set -filter {jtag_cable_name =~ "Digilent Zed*" && level==0} -index 1
fpga -f D:/sideproject/soc/final/final.sdk/design_1_wrapper_hw_platform_0/design_1_wrapper.bit

# 7. 載入暫存器內存配置，開啟強制內存讀寫控制
targets -set -nocase -filter {name =~"APU*"} -index 0
loadhw -hw D:/sideproject/soc/final/final.sdk/design_1_wrapper_hw_platform_0/system.hdf -mem-ranges [list {0x40000000 0xbfffffff}]
configparams force-mem-access 1

# 8. 執行 PS 端 MIO/DDR3 初始化腳本 (ps7_init)
puts "\[XSCT\] 正在初始化處理器系統 (ps7_init)..."
targets -set -nocase -filter {name =~"APU*"} -index 0
source D:/sideproject/soc/final/final.sdk/design_1_wrapper_hw_platform_0/ps7_init.tcl
ps7_init
ps7_post_config

# 9. 下載編譯完成的 ELF 二進制檔至 ARM Core 0
puts "\[XSCT\] 正在將測試 ELF 載入至 ARM 處理器暫存器..."
targets -set -nocase -filter {name =~ "ARM*#0"} -index 0
dow D:/sideproject/soc/final/final.sdk/ntt_test/Debug/ntt_test.elf
configparams force-mem-access 0

# 10. 啟動處理器運行，開始進行多項式加速運算
puts "\[XSCT\] 下達運行指令 (con)..."
con
puts "\[XSCT\] 加速器程式正在實體晶片上執行中！請連接 COM 埠檢視輸出。"

disconnect
exit
