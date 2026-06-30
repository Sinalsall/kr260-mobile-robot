open_project lidar_hw_ip
set_top lidar_hw_filter
add_files lidar_hw_filter.cpp
open_solution "solution1" -flow_target vivado
set_part {xck26-sfvc784-2LV-c}
create_clock -period 10 -name default
csynth_design
export_design -format ip_catalog
exit
