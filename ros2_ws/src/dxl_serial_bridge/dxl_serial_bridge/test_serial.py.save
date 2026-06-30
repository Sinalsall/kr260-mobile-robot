import rclpy
from rclpy.node import Node
import serial

class SerialTest(Node):

    def __init__(self):
        super().__init__('serial_test')

        self.ser = serial.Serial('/dev/ttyUSB0', 9600, timeout=0.1)

        self.timer = self.create_timer(0.1, self.read_serial)

        self.get_logger().info("Serial bridge started")

    def read_serial(self):
        if self.ser.in_waiting:
            line = self.ser.readline().decode().strip()
            self.get_logger().info(f"Received: {line}")

    def send_value(self, rpm1, rpm2):
        msg = f"{rpm1} {rpm2}\n"
        self.ser.write(msg.encode())
        self.get_logger().info(f"Sent: {msg.strip()}")


def main(args=None):
    rclpy.init(args=args)
    node = SerialTest()

    try:
        while rclpy.ok():
            rclpy.spin_once(node)

            user_input = input("Ketik RPM1 RPM2 (contoh: 30 -30): ")

            try:
                rpm1, rpm2 = map(float, user_input.split())
                node.send_value(rpm1, rpm2)
            except:
                print("Format salah. Contoh: 30 -30")

    except KeyboardInterrupt:
        pass

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
