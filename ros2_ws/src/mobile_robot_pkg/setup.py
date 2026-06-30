from setuptools import setup
from glob import glob
import os

package_name = 'mobile_robot_pkg'

setup(
    name=package_name,
    version='0.0.1',
    packages=[package_name],
    data_files=[
        (
            'share/ament_index/resource_index/packages',
            ['resource/' + package_name]
        ),
        (
            os.path.join('share', package_name),
            ['package.xml']
        ),
        (
            os.path.join('share', package_name, 'launch'),
            glob('launch/*.launch.py')
        ),
        (
            os.path.join('share', package_name, 'maps'),
            glob('maps/*.json')
        ),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='ubuntu',
    maintainer_email='ubuntu@localhost',
    description='Grid-based mobile robot package for computing and control units',
    license='MIT',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'computing_unit = mobile_robot_pkg.computing_unit:main',
            'control_unit = mobile_robot_pkg.control_unit:main',
        ],
    },
)
