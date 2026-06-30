#!/usr/bin/env python3

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    channel_type = LaunchConfiguration('channel_type')
    serial_port = LaunchConfiguration('serial_port')
    serial_baudrate = LaunchConfiguration('serial_baudrate')
    frame_id = LaunchConfiguration('frame_id')
    inverted = LaunchConfiguration('inverted')
    angle_compensate = LaunchConfiguration('angle_compensate')
    scan_mode = LaunchConfiguration('scan_mode')
    scan_topic = LaunchConfiguration('scan_topic')

    roi_x_min = LaunchConfiguration('roi_x_min')
    roi_x_max = LaunchConfiguration('roi_x_max')
    roi_y_margin = LaunchConfiguration('roi_y_margin')
    cluster_tolerance = LaunchConfiguration('cluster_tolerance')
    min_obj_size = LaunchConfiguration('min_obj_size')
    min_obj_points = LaunchConfiguration('min_obj_points')
    emergency_distance = LaunchConfiguration('emergency_distance')
    warning_distance = LaunchConfiguration('warning_distance')
    scan_timeout_sec = LaunchConfiguration('scan_timeout_sec')

    return LaunchDescription([
        DeclareLaunchArgument('channel_type', default_value='serial'),
        DeclareLaunchArgument('serial_port', default_value='/dev/ttyUSB0'),
        DeclareLaunchArgument('serial_baudrate', default_value='115200'),
        DeclareLaunchArgument('frame_id', default_value='laser'),
        DeclareLaunchArgument('inverted', default_value='false'),
        DeclareLaunchArgument('angle_compensate', default_value='true'),
        DeclareLaunchArgument('scan_mode', default_value='Sensitivity'),
        DeclareLaunchArgument('scan_topic', default_value='/scan'),

        DeclareLaunchArgument('roi_x_min', default_value='0.08'),
        DeclareLaunchArgument('roi_x_max', default_value='1.5'),
        DeclareLaunchArgument('roi_y_margin', default_value='0.10'),
        DeclareLaunchArgument('cluster_tolerance', default_value='0.10'),
        DeclareLaunchArgument('min_obj_size', default_value='0.06'),
        DeclareLaunchArgument('min_obj_points', default_value='3'),
        DeclareLaunchArgument('emergency_distance', default_value='0.20'),
        DeclareLaunchArgument('warning_distance', default_value='0.50'),
        DeclareLaunchArgument('scan_timeout_sec', default_value='0.5'),

        Node(
            package='sllidar_ros2',
            executable='sllidar_node',
            name='sllidar_node',
            output='screen',
            parameters=[{
                'channel_type': channel_type,
                'serial_port': serial_port,
                'serial_baudrate': serial_baudrate,
                'frame_id': frame_id,
                'inverted': inverted,
                'angle_compensate': angle_compensate,
                'scan_mode': scan_mode,
            }],
            remappings=[('scan', scan_topic)],
        ),

        Node(
            package='lidar_pl_bridge',
            executable='lidar_pl_bridge_node',
            name='lidar_filter_node',
            output='screen',
            parameters=[{
                'scan_topic': scan_topic,
                'roi_x_min': roi_x_min,
                'roi_x_max': roi_x_max,
                'roi_y_margin': roi_y_margin,
                'cluster_tolerance': cluster_tolerance,
                'min_obj_size': min_obj_size,
                'min_obj_points': min_obj_points,
                'emergency_distance': emergency_distance,
                'warning_distance': warning_distance,
                'scan_timeout_sec': scan_timeout_sec,
            }],
            remappings=[('/scan', scan_topic)],
        ),
    ])
