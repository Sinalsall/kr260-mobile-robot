# Single detected obstacle cluster

uint32 id                   # Persistent tracking ID across frames
geometry_msgs/Point centroid  # Cluster center position
float32 size                # Bounding box diameter (max dimension)
float32 width               # Bounding box width (y-dimension)
float32 length              # Bounding box length (x-dimension)
uint32 point_count          # Number of points in cluster
float32 distance            # Distance from robot origin
float32 nearest_edge        # Distance to nearest edge (x_min for forward-facing)

# Tracking information
bool is_tracked             # Whether this obstacle was matched to previous frame
float32 tracking_confidence # 0.0-1.0, based on position consistency
