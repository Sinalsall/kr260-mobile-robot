#!/usr/bin/env python3
"""
Launch file for LiDAR processing pipeline.

Loads parameters from YAML and starts the filter node
"""

from launch import LaunchDescription
from launch_ros.actions import Node
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.substitutions import FindPackageShare
import os


def generate_launch_description():
    # Get package directory
    pkg_share = FindPackageShare('lidar_spatial_filter').find('lidar_spatial_filter')

    # Default parameter file path
    default_params_file = os.path.join(pkg_share, 'config', 'lidar_filter_params.yaml')

    # Declare launch arguments
    params_file_arg = DeclareLaunchArgument(
        'params_file',
        default_value=default_params_file,
        description='Path to parameter file for lidar filter node'
    )

    use_sim_time_arg = DeclareLaunchArgument(
        'use_sim_time',
        default_value='false',
        description='Use simulation time if true'
    )

    # LiDAR filter node
    filter_node = Node(
        package='lidar_spatial_filter',
        executable='filter_node',
        name='lidar_filter_node',
        output='screen',
        parameters=[
            LaunchConfiguration('params_file'),
            {'use_sim_time': LaunchConfiguration('use_sim_time')}
        ],
        remappings=[
            # Add any topic remappings here if needed
        ]
    )

    return LaunchDescription([
        params_file_arg,
        use_sim_time_arg,
        filter_node
    ])
