import json
import math
import queue
import threading
import time

import rclpy
from rclpy.node import Node
from geometry_msgs.msg import Twist
from std_msgs.msg import String

try:
    import serial
except ImportError:
    serial = None


class ControlUnit(Node):
    def __init__(self):
        super().__init__('control_unit')

        self.target_left_rpm = 0.0
        self.target_right_rpm = 0.0
        # =========================
        # PARAMETERS
        # =========================
        self.declare_parameter('grid_size', 40) #ubah2 aja

        # Serial to Arduino
        self.declare_parameter('serial_port', '/dev/ttyUSB1')
        self.declare_parameter('serial_baud', 115200)

        # Robot geometry
        self.declare_parameter('wheel_radius_m', 0.033)        # radius roda
        self.declare_parameter('wheel_separation_m', 0.160)    # jarak antar titik tengah roda

        # Motion limit from control side
        self.declare_parameter('max_linear_x', 0.15)           # m/s
        self.declare_parameter('max_angular_z', 2.00)          # rad/s
        self.declare_parameter('max_rpm', 25.0)                # rpm

        # Safety
        self.declare_parameter('velocity_timeout_s', 0.5)

        self.grid_size = self.get_parameter('grid_size').value
        self.serial_port = self.get_parameter('serial_port').value
        self.serial_baud = self.get_parameter('serial_baud').value
        self.wheel_radius_m = self.get_parameter('wheel_radius_m').value
        self.wheel_separation_m = self.get_parameter('wheel_separation_m').value
        self.max_linear_x = self.get_parameter('max_linear_x').value
        self.max_angular_z = self.get_parameter('max_angular_z').value
        self.max_rpm = self.get_parameter('max_rpm').value
        self.velocity_timeout_s = self.get_parameter('velocity_timeout_s').value

        # =========================
        # ROS INTERFACES
        # =========================
        # User start/goal -> computing unit
        self.start_finish_pub = self.create_publisher(
            String, '/start_finish_command', 10
        )

        # Arduino feedback -> ROS
        self.feedback_pub = self.create_publisher(
            String, '/dynamixel_feedback', 10
        )

        # Optional debug topic
        self.rpm_debug_pub = self.create_publisher(
            String, '/actuator_rpm_command', 10
        )

        # Computing unit -> control unit
        self.create_subscription(
            Twist,
            '/robot_velocity_command',
            self.velocity_callback,
            10
        )

        # =========================
        # STATE
        # =========================
        self.input_queue = queue.Queue()
        self.ser = None

        # Initial pose hanya dikirim sekali dari control unit ke computing unit.
        # Setelah itu input berikutnya cukup start dan finish.
        self.initial_pose_sent = False

        self.last_velocity_time = time.monotonic()
        self.robot_stopped_by_timeout = False

        self.last_sent_left_rpm = 0.0
        self.last_sent_right_rpm = 0.0

        # =========================
        # SERIAL INIT
        # =========================
        self.connect_serial()

        # =========================
        # TIMERS
        # =========================
        self.create_timer(0.1, self.flush_input_queue)
        self.create_timer(0.01, self.read_serial_feedback)
        self.create_timer(0.1, self.check_velocity_timeout)
        self.create_timer(0.01, self.send_periodic_rpm)
        # =========================
        # INPUT THREAD
        # =========================
        self.input_thread = threading.Thread(
            target=self.console_input_worker,
            daemon=True
        )
        self.input_thread.start()

        self.get_logger().info('Control Unit siap.')
        self.get_logger().info(
            f'Params: wheel_radius={self.wheel_radius_m} m, '
            f'wheel_separation={self.wheel_separation_m} m, '
            f'max_linear_x={self.max_linear_x} m/s, '
            f'max_angular_z={self.max_angular_z} rad/s, '
            f'max_rpm={self.max_rpm}'
        )
    def send_periodic_rpm(self):
        self.send_rpm_to_arduino(
            self.target_left_rpm,
            self.target_right_rpm
        )
    # ==========================================
    # SERIAL
    # ==========================================
    def connect_serial(self):
        if serial is None:
            self.get_logger().error(
                'pyserial belum terinstall. Install dulu dengan: pip install pyserial'
            )
            return

        try:
            self.ser = serial.Serial(
                self.serial_port,
                self.serial_baud,
                timeout=0.05
            )
            time.sleep(2.0)  # tunggu Arduino reset
            self.get_logger().info(
                f'Terhubung ke Arduino di {self.serial_port} @ {self.serial_baud} bps'
            )
        except Exception as e:
            self.ser = None
            self.get_logger().error(f'Gagal konek serial ke Arduino: {e}')

    # ==========================================
    # USER INPUT START / GOAL
    # ==========================================
    def console_input_worker(self):
        while rclpy.ok():
            try:
                initial_payload = None

                # Input ini hanya diminta sekali di awal setelah control unit start.
                if not self.initial_pose_sent:
                    initial_str = input("Masukkan initial/deploy position (row,col): ").strip()
                    heading_str = input("Masukkan initial heading (NORTH/EAST/SOUTH/WEST): ").strip()

                    initial_start = self.parse_grid_coordinate(initial_str)
                    initial_heading = self.parse_heading(heading_str)

                    if initial_start is None:
                        print(f"Initial position tidak valid. Format: row,col dengan range 0-{self.grid_size - 1}")
                        continue

                    if initial_heading is None:
                        print("Initial heading tidak valid. Pilihan: NORTH, EAST, SOUTH, WEST")
                        continue

                    initial_payload = {
                        "initial_start": initial_start,
                        "initial_heading": initial_heading
                    }

                start_str = input("Masukkan start (row,col): ").strip()
                goal_str = input("Masukkan finish (row,col): ").strip()

                start = self.parse_grid_coordinate(start_str)
                goal = self.parse_grid_coordinate(goal_str)

                if start is None or goal is None:
                    print(f"Input tidak valid. Format: row,col dengan range 0-{self.grid_size - 1}")
                    continue

                if start == goal:
                    print("Start dan finish tidak boleh sama.")
                    continue

                self.input_queue.put((start, goal, initial_payload))

            except EOFError:
                break
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"Error input: {e}")

    def parse_grid_coordinate(self, text):
        try:
            parts = text.split(',')
            if len(parts) != 2:
                return None

            row = int(parts[0].strip())
            col = int(parts[1].strip())

            if not (0 <= row < self.grid_size and 0 <= col < self.grid_size):
                return None

            return [row, col]
        except Exception:
            return None

    def parse_heading(self, text):
        heading = text.strip().upper()
        if heading in ("NORTH", "EAST", "SOUTH", "WEST"):
            return heading
        return None

    def flush_input_queue(self):
        while not self.input_queue.empty():
            start, goal, initial_payload = self.input_queue.get()

            payload = {
                "start": start,
                "goal": goal
            }

            if initial_payload is not None:
                payload.update(initial_payload)

            msg = String()
            msg.data = json.dumps(payload)

            self.start_finish_pub.publish(msg)

            if initial_payload is not None:
                self.initial_pose_sent = True
                self.get_logger().info(
                    f'Kirim initial pose -> initial_start={initial_payload["initial_start"]}, '
                    f'initial_heading={initial_payload["initial_heading"]}'
                )

            self.get_logger().info(
                f'Kirim ke computing unit -> start={start}, goal={goal}'
            )

    # ==========================================
    # COMPUTING UNIT VELOCITY CALLBACK
    # ==========================================
    def velocity_callback(self, msg: Twist):
        raw_linear_x = msg.linear.x
        raw_angular_z = msg.angular.z

        # Clamp Twist dari computing unit
        linear_x = self.clamp(raw_linear_x, -self.max_linear_x, self.max_linear_x)
        angular_z = self.clamp(raw_angular_z, -self.max_angular_z, self.max_angular_z)

        twist_clamped = (
            abs(raw_linear_x - linear_x) > 1e-6 or
            abs(raw_angular_z - angular_z) > 1e-6
        )

        if twist_clamped:
            self.get_logger().warn(
                f'Twist disaturasi: '
                f'raw=({raw_linear_x:.3f}, {raw_angular_z:.3f}) '
                f'-> clamp=({linear_x:.3f}, {angular_z:.3f})'
            )

        # Konversi Twist -> RPM
        left_rpm_raw, right_rpm_raw = self.twist_to_wheel_rpm(linear_x, angular_z)

        # Clamp RPM final
        max_requested_rpm = max(abs(left_rpm_raw), abs(right_rpm_raw))

        if max_requested_rpm > self.max_rpm:
            scale_factor = self.max_rpm / max_requested_rpm
            left_rpm = left_rpm_raw * scale_factor
            right_rpm = right_rpm_raw * scale_factor
        else:
            left_rpm = left_rpm_raw
            right_rpm = right_rpm_raw

        rpm_clamped = (
            abs(left_rpm_raw - left_rpm) > 1e-6 or
            abs(right_rpm_raw - right_rpm) > 1e-6
        )

        if rpm_clamped:
            self.get_logger().warn(
                f'RPM disaturasi: '
                f'raw=({left_rpm_raw:.2f}, {right_rpm_raw:.2f}) '
                f'-> clamp=({left_rpm:.2f}, {right_rpm:.2f})'
            )

        self.target_left_rpm = left_rpm
        self.target_right_rpm = right_rpm

        self.last_velocity_time = time.monotonic()
        self.robot_stopped_by_timeout = False

        self.get_logger().info(
            f'Cmd vel diterima: linear={linear_x:.3f} m/s, angular={angular_z:.3f} rad/s '
            f'-> left_rpm={left_rpm:.2f}, right_rpm={right_rpm:.2f}'
        )

    # ==========================================
    # KINEMATICS
    # ==========================================
    def twist_to_wheel_rpm(self, linear_x, angular_z):
        # Differential drive
        # v_left  = v - (w * L / 2)
        # v_right = v + (w * L / 2)
        v_left = linear_x - (angular_z * self.wheel_separation_m / 2.0)
        v_right = linear_x + (angular_z * self.wheel_separation_m / 2.0)

        # RPM = (v / (2*pi*r)) * 60
        left_rpm = (v_left / (2.0 * math.pi * self.wheel_radius_m)) * 60.0
        right_rpm = (v_right / (2.0 * math.pi * self.wheel_radius_m)) * 60.0

        return left_rpm, right_rpm

    def clamp(self, value, min_value, max_value):
        return max(min(value, max_value), min_value)

    # ==========================================
    # SEND TO ARDUINO
    # Format: "<left_rpm> <right_rpm>\n"
    # ==========================================
    def send_rpm_to_arduino(self, left_rpm, right_rpm):
        cmd = f"{left_rpm:.2f} {right_rpm:.2f}\n"

        debug_msg = String()
        debug_msg.data = cmd.strip()
        self.rpm_debug_pub.publish(debug_msg)

        if self.ser is None:
            self.get_logger().error(
                f'Serial belum tersambung. Gagal kirim: {cmd.strip()}'
            )
            return

        try:
            self.ser.write(cmd.encode('utf-8'))
            self.last_sent_left_rpm = left_rpm
            self.last_sent_right_rpm = right_rpm
        except Exception as e:
            self.get_logger().error(f'Gagal kirim RPM ke Arduino: {e}')

    # ==========================================
    # READ FEEDBACK FROM ARDUINO
    # ==========================================
    def read_serial_feedback(self):
        if self.ser is None:
            return

        try:
            while self.ser.in_waiting > 0:
                line = self.ser.readline().decode('utf-8', errors='ignore').strip()
                if not line:
                    continue

                msg = String()
                msg.data = line
                self.feedback_pub.publish(msg)

                self.get_logger().info(f'Feedback Arduino: {line}')

        except Exception as e:
            self.get_logger().error(f'Gagal baca feedback serial: {e}')

    # ==========================================
    # FAILSAFE
    # ==========================================
    def check_velocity_timeout(self):
        elapsed = time.monotonic() - self.last_velocity_time

        if elapsed > self.velocity_timeout_s:
            self.target_left_rpm = 0.0
            self.target_right_rpm = 0.0
            self.send_rpm_to_arduino(0.0, 0.0)

            if not self.robot_stopped_by_timeout:
                self.robot_stopped_by_timeout = True
                self.get_logger().warn(
                    f'Tidak ada velocity command selama {elapsed:.2f}s. Robot dihentikan.'
                )

    # ==========================================
    # CLEANUP
    # ==========================================
    def destroy_node(self):
        try:
            if self.ser is not None:
                self.ser.write(b"0.00 0.00\n")
                time.sleep(0.1)
                self.ser.close()
        except Exception:
            pass

        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = ControlUnit()

    try:

        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
