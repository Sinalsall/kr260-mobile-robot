# ROI-based point classification
# Labels: 0=IGNORED, 1=OBSTACLE_CANDIDATE, 2=LANDMARK_CANDIDATE

std_msgs/Header header
uint32 sequence_id          # Incremental sequence for message correlation
builtin_interfaces/Time processing_start_time  # When processing began

geometry_msgs/Point[] points
uint8[] labels              # One label per point (same length as points array)

# Classification constants
uint8 IGNORED = 0
uint8 OBSTACLE_CANDIDATE = 1
uint8 LANDMARK_CANDIDATE = 2

# Statistics
uint32 total_points
uint32 obstacle_count
uint32 landmark_count
uint32 ignored_count
