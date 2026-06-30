import json
import math
import os
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from ament_index_python.packages import get_package_share_directory
from geometry_msgs.msg import Twist
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import PointCloud2
from sensor_msgs_py import point_cloud2
from std_msgs.msg import Bool, Float32, String


def finite_or_none(value):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    if math.isfinite(value):
        return value
    return None


MAP_GRID_SIZE = 40
MAP_CELL_SIZE_CM = 5
MAP_ALLOWED_VALUES = {0, 1, 3}


def _as_int(value, name):
    if isinstance(value, bool):
        raise ValueError(f'{name} must be an integer')
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        raise ValueError(f'{name} must be an integer')
    if parsed != value and not (isinstance(value, float) and value.is_integer()):
        raise ValueError(f'{name} must be an integer')
    return parsed


def _normalize_optional_cell(value, name, grid_size):
    if value is None:
        return None
    if isinstance(value, dict):
        row = value.get('row')
        col = value.get('col')
    elif isinstance(value, list) and len(value) >= 2:
        row, col = value[0], value[1]
    else:
        raise ValueError(f'{name} must be [row, col] or an object with row/col')

    row = _as_int(row, f'{name}.row')
    col = _as_int(col, f'{name}.col')
    if row < 0 or col < 0 or row >= grid_size or col >= grid_size:
        raise ValueError(f'{name} must be within 0-{grid_size - 1}')
    return {'row': row, 'col': col}


def _normalize_deployed_position(value, grid_size):
    cell = _normalize_optional_cell(value, 'deployed_position', grid_size)
    if cell is None:
        return None
    heading = 'EAST'
    if isinstance(value, dict):
        heading = str(value.get('heading', heading)).strip().upper()
    if heading not in ('NORTH', 'EAST', 'SOUTH', 'WEST'):
        raise ValueError('deployed_position.heading must be NORTH, EAST, SOUTH, or WEST')
    return {**cell, 'heading': heading}


def normalize_map_payload(payload):
    if not isinstance(payload, dict):
        raise ValueError('map payload must be a JSON object')

    source_map = payload.get('map')
    if not isinstance(source_map, list):
        raise ValueError('map must be a 2D array')

    grid_size = _as_int(payload.get('grid_size', len(source_map)), 'grid_size')
    if grid_size != MAP_GRID_SIZE:
        raise ValueError(f'grid_size must be {MAP_GRID_SIZE}')

    try:
        cell_size_cm = float(payload.get('cell_size_cm', MAP_CELL_SIZE_CM))
    except (TypeError, ValueError):
        raise ValueError('cell_size_cm must be numeric')
    if abs(cell_size_cm - MAP_CELL_SIZE_CM) > 1e-9:
        raise ValueError(f'cell_size_cm must remain {MAP_CELL_SIZE_CM}')

    if len(source_map) != grid_size:
        raise ValueError(f'map must contain {grid_size} rows')

    normalized_map = []
    for r, row in enumerate(source_map):
        if not isinstance(row, list) or len(row) != grid_size:
            raise ValueError(f'map row {r} must contain {grid_size} columns')
        normalized_row = []
        for c, value in enumerate(row):
            if isinstance(value, bool) or value not in MAP_ALLOWED_VALUES:
                raise ValueError(f'invalid cell value at ({r}, {c}): {value}')
            normalized_row.append(int(value))
        normalized_map.append(normalized_row)

    normalized = {
        'grid_size': grid_size,
        'cell_size_cm': int(cell_size_cm) if cell_size_cm.is_integer() else cell_size_cm,
        'map': normalized_map,
    }

    start = _normalize_optional_cell(payload.get('start'), 'start', grid_size)
    finish = _normalize_optional_cell(payload.get('finish'), 'finish', grid_size)
    deployed_position = _normalize_deployed_position(payload.get('deployed_position'), grid_size)
    if start is not None:
        normalized['start'] = start
    if finish is not None:
        normalized['finish'] = finish
    if deployed_position is not None:
        normalized['deployed_position'] = deployed_position

    return normalized


def write_map_payload_atomic(map_path, payload):
    path = Path(map_path)
    normalized = normalize_map_payload(payload)
    if not path.exists():
        raise FileNotFoundError(f'map file not found: {path}')

    stamp = time.strftime('%Y%m%d_%H%M%S')
    backup_path = path.with_name(f'{path.name}.bak.{stamp}.{os.getpid()}')
    tmp_path = path.with_name(f'.{path.name}.tmp.{stamp}.{os.getpid()}')

    original_stat = path.stat()
    backup_path.write_bytes(path.read_bytes())
    tmp_path.write_text(json.dumps(normalized, indent=2) + '\n', encoding='utf-8')
    os.chmod(tmp_path, original_stat.st_mode & 0o777)
    os.replace(tmp_path, path)

    return {
        'ok': True,
        'map_path': str(path),
        'backup_path': str(backup_path),
        'grid_size': normalized['grid_size'],
        'cell_size_cm': normalized['cell_size_cm'],
    }


class TelemetryStore:
    def __init__(self):
        self._lock = threading.Lock()
        self._seq = 0
        self._data = {
            'planning_status': None,
            'feedback': None,
            'velocity_command': None,
            'rpm_command': None,
            'nearest_obstacle_distance': None,
            'emergency_stop': None,
            'obstacle_points': [],
            'timestamps': {},
        }

    def update(self, key, value):
        with self._lock:
            self._data[key] = value
            self._data['timestamps'][key] = time.time()
            self._seq += 1

    def snapshot(self):
        with self._lock:
            return {
                'seq': self._seq,
                'server_time': time.time(),
                **json.loads(json.dumps(self._data)),
            }


class RobotWebUiNode(Node):
    def __init__(self):
        super().__init__('robot_web_ui')

        self.declare_parameter('host', '127.0.0.1')
        self.declare_parameter('port', 8080)
        self.declare_parameter('max_obstacle_points', 240)
        self.declare_parameter('map_path', '')

        self.host = self.get_parameter('host').value
        self.port = int(self.get_parameter('port').value)
        self.max_obstacle_points = int(self.get_parameter('max_obstacle_points').value)
        self.map_path = self._resolve_map_path(self.get_parameter('map_path').value)
        self.grid_size = self._read_map_grid_size()
        self.static_dir = Path(get_package_share_directory('robot_web_ui')) / 'static'

        self.telemetry = TelemetryStore()
        self.start_finish_pub = self.create_publisher(String, '/start_finish_command', 10)

        self.create_subscription(String, '/planning_status', self._planning_status_callback, 10)
        self.create_subscription(String, '/dynamixel_feedback', self._feedback_callback, 10)
        self.create_subscription(Twist, '/robot_velocity_command', self._velocity_callback, 10)
        self.create_subscription(String, '/actuator_rpm_command', self._rpm_command_callback, 10)
        self.create_subscription(PointCloud2, '/navigation/obstacle_points', self._obstacle_points_callback, 10)
        self.create_subscription(Float32, '/obstacle_nearest_distance', self._nearest_callback, 10)
        self.create_subscription(Bool, '/emergency_stop', self._emergency_callback, 10)

        self.httpd = ThreadingHTTPServer((self.host, self.port), RobotUiRequestHandler)
        self.httpd.node = self
        self.http_thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.http_thread.start()

        self.get_logger().info(
            f'Robot Web UI ready on http://{self.host}:{self.port} '
            f'(map={self.map_path})'
        )

    def _resolve_map_path(self, configured_path):
        if configured_path:
            return configured_path
        try:
            mobile_share = get_package_share_directory('mobile_robot_pkg')
            return os.path.join(mobile_share, 'maps', 'map.json')
        except Exception:
            return os.path.join(os.getcwd(), 'src', 'mobile_robot_pkg', 'maps', 'map.json')

    def read_default_map(self):
        with open(self.map_path, 'r', encoding='utf-8') as f:
            return json.load(f)

    def write_default_map(self, payload):
        result = write_map_payload_atomic(self.map_path, payload)
        self.grid_size = int(result['grid_size'])
        self.telemetry.update('map_saved', {
            'map_path': result['map_path'],
            'backup_path': result['backup_path'],
            'saved_at': time.time(),
        })
        return result

    def _read_map_grid_size(self):
        try:
            data = self.read_default_map()
            if isinstance(data, dict):
                if 'grid_size' in data:
                    return int(data['grid_size'])
                if isinstance(data.get('map'), list):
                    return len(data['map'])
            if isinstance(data, list):
                return len(data)
        except Exception as exc:
            self.get_logger().warn(f'Failed to read map grid size: {exc}')
        return 40

    def publish_start_finish(self, start, goal, initial_pose=None):
        payload = {'start': start, 'goal': goal}
        if initial_pose is not None:
            payload.update({
                'initial_start': initial_pose['initial_start'],
                'initial_heading': initial_pose['initial_heading'],
            })

        msg = String()
        msg.data = json.dumps(payload)
        self.start_finish_pub.publish(msg)

    def _planning_status_callback(self, msg):
        try:
            value = json.loads(msg.data)
        except json.JSONDecodeError:
            value = {'raw': msg.data, 'parse_error': True}
        self.telemetry.update('planning_status', value)

    def _feedback_callback(self, msg):
        self.telemetry.update('feedback', self._parse_feedback(msg.data))

    def _velocity_callback(self, msg):
        self.telemetry.update('velocity_command', {
            'linear_x': round(float(msg.linear.x), 4),
            'angular_z': round(float(msg.angular.z), 4),
        })

    def _rpm_command_callback(self, msg):
        parts = msg.data.replace(',', ' ').split()
        parsed = {'raw': msg.data}
        if len(parts) >= 2:
            left = finite_or_none(parts[0])
            right = finite_or_none(parts[1])
            if left is not None and right is not None:
                parsed.update({'left_rpm': round(left, 2), 'right_rpm': round(right, 2)})
        self.telemetry.update('rpm_command', parsed)

    def _obstacle_points_callback(self, msg):
        points = []
        try:
            for idx, p in enumerate(point_cloud2.read_points(msg, field_names=('x', 'y', 'z'), skip_nans=True)):
                if idx >= self.max_obstacle_points:
                    break
                x = finite_or_none(p[0])
                y = finite_or_none(p[1])
                z = finite_or_none(p[2])
                if x is not None and y is not None:
                    points.append({'x': round(x, 4), 'y': round(y, 4), 'z': round(z or 0.0, 4)})
        except Exception as exc:
            self.get_logger().warn(f'Failed to parse obstacle PointCloud2: {exc}')
        self.telemetry.update('obstacle_points', points)

    def _nearest_callback(self, msg):
        self.telemetry.update('nearest_obstacle_distance', finite_or_none(msg.data))

    def _emergency_callback(self, msg):
        self.telemetry.update('emergency_stop', bool(msg.data))

    def _parse_feedback(self, line):
        parts = line.strip().replace(',', ' ').split()
        parsed = {'raw': line.strip()}
        if len(parts) >= 19 and parts[0] == 'FB':
            left = finite_or_none(parts[1])
            right = finite_or_none(parts[2])
            try:
                sensors = [int(p) for p in parts[3:19]]
            except ValueError:
                sensors = []
            parsed.update({
                'left_rpm': round(left, 2) if left is not None else None,
                'right_rpm': round(right, 2) if right is not None else None,
                'line_sensors': sensors,
            })
        return parsed

    def destroy_node(self):
        if hasattr(self, 'httpd'):
            self.httpd.shutdown()
            self.httpd.server_close()
        super().destroy_node()


class RobotUiRequestHandler(BaseHTTPRequestHandler):
    server_version = 'RobotWebUI/0.1'

    def log_message(self, fmt, *args):
        self.server.node.get_logger().debug(fmt % args)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/':
            self._serve_static('index.html')
        elif path == '/api/map':
            self._serve_map()
        elif path == '/events':
            self._serve_events()
        else:
            name = path.lstrip('/')
            self._serve_static(name)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == '/api/navigation/start':
            self._handle_start_navigation()
        elif path == '/api/map':
            self._handle_save_map()
        else:
            self._json_response({'error': 'not found'}, HTTPStatus.NOT_FOUND)

    def _serve_static(self, name):
        path = Path(name)
        if path.is_absolute() or '..' in path.parts:
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        target = self.server.node.static_dir / path
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        content_type = 'text/plain'
        if target.suffix == '.html':
            content_type = 'text/html; charset=utf-8'
        elif target.suffix == '.css':
            content_type = 'text/css; charset=utf-8'
        elif target.suffix == '.js':
            content_type = 'application/javascript; charset=utf-8'

        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def _serve_map(self):
        try:
            data = self.server.node.read_default_map()
        except Exception as exc:
            self._json_response({'error': str(exc)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        self._json_response(data)

    def _serve_events(self):
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()

        last_seq = -1
        while rclpy.ok():
            snapshot = self.server.node.telemetry.snapshot()
            if snapshot['seq'] != last_seq:
                last_seq = snapshot['seq']
                payload = json.dumps(snapshot, separators=(',', ':'))
                try:
                    self.wfile.write(f'event: telemetry\ndata: {payload}\n\n'.encode('utf-8'))
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    break
            time.sleep(0.2)

    def _read_json_body(self, max_bytes=256 * 1024):
        content_len = int(self.headers.get('Content-Length', '0'))
        if content_len <= 0:
            raise ValueError('empty request body')
        if content_len > max_bytes:
            raise ValueError('request body too large')
        body = self.rfile.read(content_len).decode('utf-8')
        return json.loads(body)

    def _handle_save_map(self):
        try:
            data = self._read_json_body()
            result = self.server.node.write_default_map(data)
        except json.JSONDecodeError as exc:
            self._json_response({'error': f'invalid JSON: {exc}'}, HTTPStatus.BAD_REQUEST)
            return
        except ValueError as exc:
            self._json_response({'error': str(exc)}, HTTPStatus.BAD_REQUEST)
            return
        except Exception as exc:
            self.server.node.get_logger().error(f'Failed to save map: {exc}')
            self._json_response({'error': str(exc)}, HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._json_response(result)

    def _handle_start_navigation(self):
        try:
            content_len = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(content_len).decode('utf-8')
            data = json.loads(body)
            start = self._validate_cell(data.get('start'), 'start')
            goal = self._validate_cell(data.get('goal'), 'goal')
            initial_pose = self._extract_initial_pose(data)
        except Exception as exc:
            self._json_response({'error': str(exc)}, HTTPStatus.BAD_REQUEST)
            return

        self.server.node.publish_start_finish(start, goal, initial_pose)
        response = {'ok': True, 'start': start, 'goal': goal}
        if initial_pose is not None:
            response['initial_pose'] = initial_pose
        self._json_response(response)

    def _validate_cell(self, value, name):
        if not isinstance(value, list) or len(value) != 2:
            raise ValueError(f'{name} must be [row, col]')
        row = int(value[0])
        col = int(value[1])
        if row < 0 or col < 0:
            raise ValueError(f'{name} must be non-negative')
        grid_size = getattr(self.server.node, 'grid_size', 40)
        if row >= grid_size or col >= grid_size:
            raise ValueError(f'{name} must be within 0-{grid_size - 1}')
        return [row, col]

    def _extract_initial_pose(self, data):
        if data.get('initial_pose') is not None:
            return self._validate_initial_pose(data.get('initial_pose'))

        if data.get('initial_start') is None and data.get('initial_heading') is None:
            return None

        return self._validate_initial_pose({
            'start': data.get('initial_start'),
            'heading': data.get('initial_heading'),
        })

    def _validate_initial_pose(self, value):
        if value is None:
            return None
        if not isinstance(value, dict):
            raise ValueError('initial_pose must be an object')

        if 'start' in value:
            initial_start = self._validate_cell(value.get('start'), 'initial_pose.start')
        else:
            initial_start = self._validate_cell([value.get('row'), value.get('col')], 'initial_pose')

        heading = str(value.get('heading', '')).strip().upper()
        if heading not in ('NORTH', 'EAST', 'SOUTH', 'WEST'):
            raise ValueError('initial_pose.heading must be NORTH, EAST, SOUTH, or WEST')

        return {
            'initial_start': initial_start,
            'initial_heading': heading,
        }

    def _json_response(self, data, status=HTTPStatus.OK):
        payload = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(payload)


def main(args=None):
    rclpy.init(args=args)
    node = RobotWebUiNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
