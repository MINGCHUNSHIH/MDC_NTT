# =============================================================================
# Vivado 專案重建與自動編譯 Tcl 腳本 (rebuild.tcl)
# 適用環境: Vivado 2019.1 (或相容版本)
# 功能描述:
#   1. 同步最新的 RTL 與 Testbench 原始碼至 Vivado 專案工作目錄。
#   2. 開啟 Vivado 專案 (.xpr)。
#   3. 自動更新 IP 目錄，升級 Block Design 中的 topsoft 加速器 IP。
#   4. 重置 Block Design 目標並清除過期的 Out-of-Context (OOC) 快取。
#   5. 重新生成 Block Design 設計網表與管腳約束。
#   6. 配置高時序收斂策略 (Flow_PerfOptimized_high 與 Performance_Explore)。
#   7. 執行綜合 (Synthesis) 與佈局佈線 (Implementation)，生成二進制 Bitstream。
#   8. 匯出最新的硬體平台檔案 (.hdf)，供 Xilinx SDK 進行軟體驗證使用。
# =============================================================================

# -----------------------------------------------------------------------------
# 0. 同步 RTL 原始碼 (保持 Block Design 設計與 Git Repos 同步)
# -----------------------------------------------------------------------------
set src_repo "D:/sideproject/Dilithium_MDC_NTT_Accelerator"
set dest_dir "D:/sideproject/soc/final/src"

puts "\[Sync\] 正在同步 RTL 與 Testbench 檔案至 Vivado 專案..."
if {[file exists $src_repo]} {
    # 複製 rtl/core 中的硬體核心運算檔案
    foreach f [glob -nocomplain "$src_repo/rtl/core/*.v"] {
        file copy -force $f $dest_dir
    }
    # 複製 rtl/top 中的 AXI-Stream 頂層封裝檔案
    foreach f [glob -nocomplain "$src_repo/rtl/top/*.v"] {
        file copy -force $f $dest_dir
    }
    # 複製 tb 中的記憶體初始化與 SystemVerilog 驗證檔案
    foreach f [glob -nocomplain "$src_repo/tb/*.mem"] {
        file copy -force $f $dest_dir
    }
    foreach f [glob -nocomplain "$src_repo/tb/*.sv"] {
        file copy -force $f $dest_dir
    }
    puts "\[Sync\] 同步完成。"
} else {
    puts "\[WARNING\] 未找到 Git 倉庫路徑 $src_repo，跳過同步。"
}

# -----------------------------------------------------------------------------
# 1. 開啟 Vivado 專案
# -----------------------------------------------------------------------------
open_project D:/sideproject/soc/final/final.xpr

# -----------------------------------------------------------------------------
# 2. 設定專案頂層 Wrapper 模組，並更新編譯鏈順序
# -----------------------------------------------------------------------------
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# 3. 升級 Block Design 內部的加速器 IP 核心
# -----------------------------------------------------------------------------
update_ip_catalog -rebuild
upgrade_ip -log ip_upgrade.log [get_ips design_1_topsoft_0_0]

# -----------------------------------------------------------------------------
# 4. 開啟 Block Design 並重置目標，清除過期運算檔案
# -----------------------------------------------------------------------------
open_bd_design D:/sideproject/soc/final/final.srcs/sources_1/bd/design_1/design_1.bd
reset_target all [get_files D:/sideproject/soc/final/final.srcs/sources_1/bd/design_1/design_1.bd]
export_ip_user_files -of_objects [get_files D:/sideproject/soc/final/final.srcs/sources_1/bd/design_1/design_1.bd] -sync -no_script -force -quiet

# -----------------------------------------------------------------------------
# 5. 重新生成 Block Design 實體網表
# -----------------------------------------------------------------------------
generate_target all [get_files D:/sideproject/soc/final/final.srcs/sources_1/bd/design_1/design_1.bd]

# -----------------------------------------------------------------------------
# 6. 清除 IP 快取，並重置綜合與實作執行檔
# -----------------------------------------------------------------------------
config_ip_cache -clear_local_cache
reset_run synth_1
reset_run impl_1

# -----------------------------------------------------------------------------
# 6c. 配置高效能綜合與佈局佈線時序策略 (確保時序收斂)
# -----------------------------------------------------------------------------
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_Explore [get_runs impl_1]

# -----------------------------------------------------------------------------
# 7. 啟動綜合、實作並生成 Bitstream 二進制檔案 (採用 12 個邏輯執行緒平行加速)
# -----------------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 12
wait_on_run impl_1

# -----------------------------------------------------------------------------
# 8. 匯出硬體手口檔 (Hardware Specification File, .hdf)，提供給 Xilinx SDK
# -----------------------------------------------------------------------------
file mkdir D:/sideproject/soc/final/final.sdk
open_bd_design D:/sideproject/soc/final/final.srcs/sources_1/bd/design_1/design_1.bd
write_sysdef -force -hwdef D:/sideproject/soc/final/final.srcs/sources_1/bd/design_1/synth/design_1.hwdef -bit D:/sideproject/soc/final/final.runs/impl_1/design_1_wrapper.bit -file D:/sideproject/soc/final/final.sdk/design_1_wrapper.hdf

puts "\[Build\] Vivado 全自動編譯與硬體匯出完成！"
