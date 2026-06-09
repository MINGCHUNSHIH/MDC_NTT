# =============================================================================
# Vivado 一鍵從零重建專案、自動拉線與編譯主控 Tcl 腳本 (rebuild_project_from_scratch.tcl)
# 適用環境: Vivado 2019.1
# 功能描述:
#   1. 在當前目錄下建立全新的 Vivado 專案 (project_from_scratch)。
#   2. 設定目標板為 ZedBoard (BOARD_PART em.avnet.com:zed:part0:1.4)。
#   3. 將自訂加速器 IP 目錄 (包含 component.xml) 加入 IP 倉庫路徑，使 Vivado 能識別 topsoft 加速器。
#   4. 執行 (source) design_1.tcl，自動重建整個 Block Design 並將所有線路拉好。
#   5. 自動產生頂層 HDL 封裝檔案 (Wrapper) 並加入編譯源。
#   6. 啟動綜合與實作佈局佈線，最終生成用於實體板端燒錄的 Bitstream 檔案。
# =============================================================================

# 1. 定義路徑
set proj_name "project_from_scratch"
set proj_dir "./project_from_scratch"
# 自訂 IP 所在的目錄 (包含 component.xml 與 xgui)，我們直接指向原來的 soc/final 目錄
set ip_repo_dir [file normalize "[file join [file dirname [info script]] ../rtl]"]

# 2. 建立全新專案，並配置開發板為 ZedBoard
puts "\[Scratch Build\] 正在建立全新專案 $proj_name..."
create_project -force $proj_name $proj_dir -part xc7z020clg484-1
set_property BOARD_PART em.avnet.com:zed:part0:1.4 [current_project]

# 3. 配置 IP 倉庫路徑，確保 Vivado 能找到自訂的 topsoft 加速器 IP
puts "\[Scratch Build\] 正在設定 IP 倉庫路徑..."
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog -rebuild

# 4. 載入並執行 Block Design 重建腳本 (自動放進元件並將所有線路拉好)
puts "\[Scratch Build\] 正在加載 Block Design 並自動執行連線..."
source [file join [file dirname [info script]] design_1.tcl]

# 5. 驗證與存檔 Block Design
validate_bd_design
save_bd_design

# 6. 自動產生頂層 HDL Wrapper 並加入編譯源
puts "\[Scratch Build\] 正在自動產生頂層 HDL Wrapper..."
set bd_file [get_files -norecurse *.bd]
make_wrapper -files [get_files $bd_file] -top
add_files -norecurse [file normalize [glob -nocomplain "${proj_dir}/${proj_name}.srcs/sources_1/bd/design_1/hdl/design_1_wrapper.v"]]
update_compile_order -fileset sources_1

# 7. 重置並啟動綜合與實作 (生成 Bitstream)
puts "\[Scratch Build\] 正在啟動綜合與實作佈局佈線，請耐心等待..."
launch_runs impl_1 -to_step write_bitstream -jobs 12
wait_on_run impl_1

puts "\[Scratch Build\] 一鍵重建專案、自動拉線與編譯全部完成！"
