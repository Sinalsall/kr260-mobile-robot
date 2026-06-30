# Array of detected landmarks

std_msgs/Header header
uint32 sequence_id          # Incremental sequence for message correlation
builtin_interfaces/Time processing_start_time  # When processing began

Landmark[] landmarks
uint32 corner_count         # Number of corner landmarks
uint32 edge_count           # Number of edge landmarks
uint32 pole_count           # Number of pole landmarks
