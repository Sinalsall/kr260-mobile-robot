from launch import LaunchDescription
from launch_ros.actions import Node
from ament_index_python.packages import get_package_share_directory
import os


def generate_launch_description():
    pkg_share = get_package_share_directory('mobile_robot_pkg')
    map_path = os.path.join(pkg_share, 'maps', 'map.json')

    computing_unit_node = Node(
        package='mobile_robot_pkg',
        executable='computing_unit',
        name='computing_unit',
        output='screen',
        parameters=[{
            'map_path': map_path,

            # Movement parameters
            'max_linear_x': 0.12,
            'max_angular_z': 1.20,
            'k_linear': 1.2,
            'k_angular_rotate': 2.0,
            'k_angular_move': 1.5,
            'min_linear_x': 0.015,

            # Navigation parameters
            'heading_tolerance_deg': 5.0,
            'cell_reached_tolerance_m': 0.015,
            'control_period_s': 0.05,
            'feedback_timeout_s': 0.5,
            'stop_dwell_s': 0.10,
        }]
    )

    return LaunchDescription([
        computing_unit_node
    ])