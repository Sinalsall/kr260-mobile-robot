cmake_minimum_required(VERSION 3.8)
project(lidar_pl_accel)
if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(visualization_msgs REQUIRED)
find_package(std_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(lidar_spatial_filter REQUIRED)
add_executable(lidar_pl_node src/lidar_pl_node.cpp)
target_include_directories(lidar_pl_node PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:include>)
target_compile_features(lidar_pl_node PUBLIC c_std_99 cxx_std_17)
ament_target_dependencies(
  lidar_pl_node
  rclcpp
  sensor_msgs
  visualization_msgs
  std_msgs
  geometry_msgs
  lidar_spatial_filter
)
install(TARGETS lidar_pl_node
  DESTINATION lib/${PROJECT_NAME})
ament_package()
