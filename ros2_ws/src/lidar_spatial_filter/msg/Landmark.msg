# Detected landmark feature

uint8 type                  # Landmark type
geometry_msgs/Point position  # Landmark position in robot frame
float32 angle               # Interior angle for corners (degrees)
float32 confidence          # Detection confidence (0.0-1.0)

# Landmark type constants
uint8 CORNER = 0
uint8 EDGE = 1
uint8 POLE = 2

# Detection metadata
uint32 supporting_points    # Number of points supporting this landmark
uint32 persistence_count    # Number of consecutive scans detected
bool is_stable              # Whether landmark passed temporal filtering
