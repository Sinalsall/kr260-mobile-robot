# Array of detected obstacles

std_msgs/Header header
uint32 sequence_id          # Incremental sequence for message correlation
builtin_interfaces/Time processing_start_time  # When processing began

Obstacle[] obstacles
float32 nearest_obstacle_distance  # Minimum distance to any validated obstacle
uint32 total_clusters       # Total clusters detected (including filtered)
uint32 validated_obstacles  # Obstacles passing size/point validation

# Safety zones
bool emergency_zone_occupied   # Any obstacle closer than emergency threshold
bool warning_zone_occupied     # Any obstacle in warning zone
