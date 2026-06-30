#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/laser_scan.hpp"
#include "visualization_msgs/msg/marker_array.hpp"
#include "std_msgs/msg/float32.hpp"
#include "std_msgs/msg/bool.hpp"
#include <cmath>
#include <vector>
#include <algorithm>
#include <limits>
#include <chrono>

using std::placeholders::_1;

// ===== PERFORMANCE TIMING STRUCTURE =====
struct PipelineTiming {
    double filtering_ms = 0.0;
    double clustering_ms = 0.0;
    double total_ms = 0.0;
    
    void reset() {
        filtering_ms = 0.0;
        clustering_ms = 0.0;
        total_ms = 0.0;
    }
};

class LidarFilterNode : public rclcpp::Node {
public:
    LidarFilterNode() : Node("lidar_filter_node"), sequence_id_(0) {

        // ===== NAMESPACED ROS 2 PARAMETERS =====
        // Filter Parameters
        this->declare_parameter("filter.range_min", 0.15);
        this->declare_parameter("filter.range_max", 3.0);
        
        // ROI Parameters (trapezoid shape)
        this->declare_parameter("roi.x_min", 0.3);        // Near distance
        this->declare_parameter("roi.x_max", 1.0);        // Far distance
        this->declare_parameter("roi.y_base", 0.2);       // Half-width at near distance
        this->declare_parameter("roi.y_expansion_rate", 0.1);  // Width increase per meter

        // Clustering Parameters
        this->declare_parameter("cluster.tolerance", 0.10);
        this->declare_parameter("cluster.min_obj_size", 0.06);
        this->declare_parameter("cluster.min_points", 3);

        // Safety Zone Parameters
        this->declare_parameter("safety.emergency_distance", 0.20);
        this->declare_parameter("safety.warning_distance", 0.50);

        // System Parameters
        this->declare_parameter("system.scan_timeout_sec", 0.5);
        this->declare_parameter("system.scan_topic", std::string("/scan"));
        this->declare_parameter("system.enable_timing", true);
        this->declare_parameter("system.timing_log_interval", 50);  // Log every N scans

        // Load parameters
        loadParameters();

        // ===== QoS & SUBSCRIBER =====
        auto qos = rclcpp::SensorDataQoS();
        scan_sub_ = this->create_subscription<sensor_msgs::msg::LaserScan>(
            scan_topic_, qos, std::bind(&LidarFilterNode::scan_callback, this, _1));

        // ===== PUBLISHERS =====
        marker_pub_   = this->create_publisher<visualization_msgs::msg::MarkerArray>("/obstacle_boxes", 10);
        nearest_pub_  = this->create_publisher<std_msgs::msg::Float32>("/obstacle_nearest_distance", 10);
        estop_pub_    = this->create_publisher<std_msgs::msg::Bool>("/emergency_stop", 10);

        // ===== WATCHDOG TIMER =====
        last_scan_time_ = this->now();
        watchdog_timer_ = this->create_wall_timer(
            std::chrono::milliseconds(static_cast<int>(scan_timeout_ * 1000)),
            std::bind(&LidarFilterNode::watchdog_callback, this));

        // ===== DYNAMIC PARAMETER CALLBACK =====
        param_cb_handle_ = this->add_on_set_parameters_callback(
            std::bind(&LidarFilterNode::on_parameter_change, this, _1));

        RCLCPP_INFO(this->get_logger(),
            "Lidar Filter Node (Modular) Active. ROI trapezoid: x=[%.2f, %.2f]m y_base=±%.2fm expansion=%.2fm/m",
            roi_x_min_, roi_x_max_, roi_y_base_, roi_y_expansion_rate_);
        RCLCPP_INFO(this->get_logger(), 
            "Safety zones: Emergency<%.2fm Warning<%.2fm | Timing: %s",
            emergency_dist_, warning_dist_, enable_timing_ ? "ENABLED" : "disabled");
    }

private:
    // ===== DATA STRUCTURES =====
    struct Point { float x, y; };
    
    struct BoundingBox {
        float x_min, x_max, y_min, y_max;
        int point_count;
    };

    // ===== TUNABLE PARAMETERS =====
    // Filter
    double filter_range_min_, filter_range_max_;
    
    // ROI (trapezoid)
    double roi_x_min_, roi_x_max_;
    double roi_y_base_, roi_y_expansion_rate_;
    
    // Clustering
    double cluster_tol_;
    double min_obj_size_;
    int min_obj_points_;
    
    // Safety
    double emergency_dist_, warning_dist_;
    
    // System
    double scan_timeout_;
    std::string scan_topic_;
    bool enable_timing_;
    int timing_log_interval_;

    // ===== STATE =====
    rclcpp::Time last_scan_time_;
    int prev_marker_count_ = 0;
    uint32_t sequence_id_;
    PipelineTiming timing_;
    int scan_count_ = 0;

    // ===== PARAMETER MANAGEMENT =====
    void loadParameters() {
        // Filter
        filter_range_min_ = this->get_parameter("filter.range_min").as_double();
        filter_range_max_ = this->get_parameter("filter.range_max").as_double();
        
        // ROI
        roi_x_min_ = this->get_parameter("roi.x_min").as_double();
        roi_x_max_ = this->get_parameter("roi.x_max").as_double();
        roi_y_base_ = this->get_parameter("roi.y_base").as_double();
        roi_y_expansion_rate_ = this->get_parameter("roi.y_expansion_rate").as_double();
        
        // Clustering
        cluster_tol_ = this->get_parameter("cluster.tolerance").as_double();
        min_obj_size_ = this->get_parameter("cluster.min_obj_size").as_double();
        min_obj_points_ = this->get_parameter("cluster.min_points").as_int();
        
        // Safety
        emergency_dist_ = this->get_parameter("safety.emergency_distance").as_double();
        warning_dist_ = this->get_parameter("safety.warning_distance").as_double();
        
        // System
        scan_timeout_ = this->get_parameter("system.scan_timeout_sec").as_double();
        scan_topic_ = this->get_parameter("system.scan_topic").as_string();
        enable_timing_ = this->get_parameter("system.enable_timing").as_bool();
        timing_log_interval_ = this->get_parameter("system.timing_log_interval").as_int();
    }

    rcl_interfaces::msg::SetParametersResult on_parameter_change(
        const std::vector<rclcpp::Parameter> & params)
    {
        for (const auto & p : params) {
            const std::string& name = p.get_name();
            
            // Filter parameters
            if (name == "filter.range_min") filter_range_min_ = p.as_double();
            else if (name == "filter.range_max") filter_range_max_ = p.as_double();
            
            // ROI parameters
            else if (name == "roi.x_min") roi_x_min_ = p.as_double();
            else if (name == "roi.x_max") roi_x_max_ = p.as_double();
            else if (name == "roi.y_base") roi_y_base_ = p.as_double();
            else if (name == "roi.y_expansion_rate") roi_y_expansion_rate_ = p.as_double();
            
            // Clustering parameters
            else if (name == "cluster.tolerance") cluster_tol_ = p.as_double();
            else if (name == "cluster.min_obj_size") min_obj_size_ = p.as_double();
            else if (name == "cluster.min_points") min_obj_points_ = p.as_int();
            
            // Safety parameters
            else if (name == "safety.emergency_distance") emergency_dist_ = p.as_double();
            else if (name == "safety.warning_distance") warning_dist_ = p.as_double();
            
            // System parameters
            else if (name == "system.enable_timing") enable_timing_ = p.as_bool();
            else if (name == "system.timing_log_interval") timing_log_interval_ = p.as_int();
        }
        
        rcl_interfaces::msg::SetParametersResult result;
        result.successful = true;
        return result;
    }

    // ===== WATCHDOG: Detect LiDAR failure =====
    void watchdog_callback() {
        double elapsed = (this->now() - last_scan_time_).seconds();
        
        if (elapsed > scan_timeout_) {
            RCLCPP_WARN_THROTTLE(this->get_logger(), *this->get_clock(), 2000,
                "WATCHDOG: No /scan received for %.1f sec! Publishing E-STOP.", elapsed);
            
            std_msgs::msg::Bool estop;
            estop.data = true;
            estop_pub_->publish(estop);
        }
    }

    // ===== STAGE 1: SPATIAL FILTERING =====
    // PL Note: Fully parallelizable per-point operation
    // Fixed-point: Q16.16 for range comparisons, trig via CORDIC or LUT
    void applySpatialFilter(
        const sensor_msgs::msg::LaserScan::SharedPtr& msg,
        std::vector<Point>& filtered_points,
        float& nearest_raw_dist)
    {
        auto t_start = std::chrono::high_resolution_clock::now();
        
        filtered_points.clear();
        nearest_raw_dist = std::numeric_limits<float>::infinity();
        
        // Calculate trapezoid ROI width at different distances
        // PL Note: Linear interpolation, can be done with fixed-point multiply-add
        auto calcROIWidth = [this](float x) -> float {
            return roi_y_base_ + x * roi_y_expansion_rate_;
        };
        
        for (size_t i = 0; i < msg->ranges.size(); ++i) {
            float r = msg->ranges[i];
            
            // Basic range filtering
            if (r < msg->range_min || r > msg->range_max || 
                std::isnan(r) || std::isinf(r)) continue;
            
            // Additional range filter
            if (r < filter_range_min_ || r > filter_range_max_) continue;
            
            // Polar to Cartesian
            // PL Note: Use CORDIC or LUT for sin/cos (8-10 bit angle precision sufficient)
            float theta = msg->angle_min + i * msg->angle_increment;
            float x = r * std::cos(theta);  // PL: CORDIC or cos LUT
            float y = r * std::sin(theta);  // PL: CORDIC or sin LUT
            
            // Check if point is in trapezoid ROI
            // PL Note: Simple comparisons, fully parallelizable
            if (x >= roi_x_min_ && x <= roi_x_max_) {
                float roi_width = calcROIWidth(x);
                if (std::abs(y) <= roi_width) {  // PL: abs via XOR with sign bit
                    filtered_points.push_back({x, y});
                    
                    // Track nearest raw distance
                    // PL Note: sqrt approximation or compare squared distances
                    float dist = std::sqrt(x * x + y * y);  // PL: Fast inverse sqrt or LUT
                    nearest_raw_dist = std::min(nearest_raw_dist, dist);
                }
            }
        }
        
        if (enable_timing_) {
            auto t_end = std::chrono::high_resolution_clock::now();
            timing_.filtering_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();
        }
    }

    // ===== STAGE 2: OBSTACLE CLUSTERING =====
    // PL Note: Sequential radial clustering is streaming-friendly for FPGA
    // Processes points in scan order, minimal memory buffering needed
    void clusterObstacles(
        const std::vector<Point>& filtered_points,
        std::vector<BoundingBox>& clusters)
    {
        auto t_start = std::chrono::high_resolution_clock::now();
        
        clusters.clear();
        
        if (filtered_points.empty()) {
            if (enable_timing_) {
                auto t_end = std::chrono::high_resolution_clock::now();
                timing_.clustering_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();
            }
            return;
        }
        
        // Start first cluster
        BoundingBox current_box = {
            filtered_points[0].x, filtered_points[0].x,
            filtered_points[0].y, filtered_points[0].y, 1
        };
        
        // PL Note: This loop processes sequentially but is pipeline-friendly
        // Each iteration: compute center, half-widths, edge distance, compare
        for (size_t i = 1; i < filtered_points.size(); ++i) {
            // Distance to current bounding box center
            // PL Note: All operations are fixed-point friendly
            float dx_to_center = filtered_points[i].x - (current_box.x_min + current_box.x_max) / 2.0f;
            float dy_to_center = filtered_points[i].y - (current_box.y_min + current_box.y_max) / 2.0f;
            
            // Distance to nearest edge of bounding box
            float half_w = (current_box.x_max - current_box.x_min) / 2.0f;
            float half_h = (current_box.y_max - current_box.y_min) / 2.0f;
            float dx_edge = std::max(0.0f, std::abs(dx_to_center) - half_w);
            float dy_edge = std::max(0.0f, std::abs(dy_to_center) - half_h);
            
            // PL Note: sqrt can be replaced with squared distance comparison
            float dist_to_box = std::sqrt(dx_edge * dx_edge + dy_edge * dy_edge);
            
            if (dist_to_box <= cluster_tol_) {
                // Extend current cluster
                // PL Note: min/max operations are single-cycle in hardware
                current_box.x_min = std::min(current_box.x_min, filtered_points[i].x);
                current_box.x_max = std::max(current_box.x_max, filtered_points[i].x);
                current_box.y_min = std::min(current_box.y_min, filtered_points[i].y);
                current_box.y_max = std::max(current_box.y_max, filtered_points[i].y);
                current_box.point_count++;
            } else {
                // Save old cluster, start new one
                clusters.push_back(current_box);
                current_box = {
                    filtered_points[i].x, filtered_points[i].x,
                    filtered_points[i].y, filtered_points[i].y, 1
                };
            }
        }
        
        // Don't forget last cluster
        clusters.push_back(current_box);
        
        if (enable_timing_) {
            auto t_end = std::chrono::high_resolution_clock::now();
            timing_.clustering_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();
        }
    }

    // ===== STAGE 3: CLUSTER VALIDATION & VISUALIZATION =====
    void processValidatedClusters(
        const std::vector<BoundingBox>& clusters,
        const sensor_msgs::msg::LaserScan::SharedPtr& msg,
        float& nearest_validated_dist,
        bool& emergency_flag)
    {
        visualization_msgs::msg::MarkerArray marker_array;
        
        // Delete old markers efficiently
        for (int i = 0; i < prev_marker_count_; ++i) {
            visualization_msgs::msg::Marker del;
            del.header.frame_id = msg->header.frame_id;
            del.header.stamp = msg->header.stamp;
            del.ns = "obstacles";
            del.id = i;
            del.action = visualization_msgs::msg::Marker::DELETE;
            marker_array.markers.push_back(del);
        }
        
        int id = 0;
        nearest_validated_dist = std::numeric_limits<float>::infinity();
        emergency_flag = false;
        
        for (const auto& box : clusters) {
            float obj_width  = box.y_max - box.y_min;
            float obj_length = box.x_max - box.x_min;
            
            // Validate obstacle (filter noise)
            if ((obj_width >= min_obj_size_ || obj_length >= min_obj_size_) &&
                 box.point_count >= min_obj_points_) {
                
                // Track nearest validated obstacle
                nearest_validated_dist = std::min(nearest_validated_dist, box.x_min);
                
                if (box.x_min < emergency_dist_) {
                    emergency_flag = true;
                }
                
                // Create visualization marker
                visualization_msgs::msg::Marker marker;
                marker.header.frame_id = msg->header.frame_id;
                marker.header.stamp = msg->header.stamp;
                marker.ns = "obstacles";
                marker.id = id++;
                marker.type = visualization_msgs::msg::Marker::CUBE;
                marker.action = visualization_msgs::msg::Marker::ADD;
                
                marker.pose.position.x = (box.x_min + box.x_max) / 2.0;
                marker.pose.position.y = (box.y_min + box.y_max) / 2.0;
                marker.pose.position.z = 0.0;
                marker.pose.orientation.w = 1.0;
                
                marker.scale.x = std::max(0.06f, obj_length);
                marker.scale.y = std::max(0.06f, obj_width);
                marker.scale.z = 0.2;
                
                // Color based on danger zone
                if (box.x_min < emergency_dist_) {
                    marker.color.r = 1.0f; marker.color.g = 0.0f; marker.color.b = 0.0f;
                    marker.color.a = 0.8f;
                } else if (box.x_min < warning_dist_) {
                    marker.color.r = 1.0f; marker.color.g = 0.8f; marker.color.b = 0.0f;
                    marker.color.a = 0.6f;
                } else {
                    marker.color.r = 1.0f; marker.color.g = 0.0f; marker.color.b = 0.0f;
                    marker.color.a = 0.4f;
                }
                
                marker.lifetime = rclcpp::Duration::from_seconds(0.3);
                marker_array.markers.push_back(marker);
            }
        }
        
        prev_marker_count_ = id;
        marker_pub_->publish(marker_array);
    }

    // ===== MAIN SCAN CALLBACK (Pipeline Orchestrator) =====
    void scan_callback(const sensor_msgs::msg::LaserScan::SharedPtr msg) {
        auto t_pipeline_start = std::chrono::high_resolution_clock::now();
        
        last_scan_time_ = this->now();
        sequence_id_++;
        scan_count_++;
        
        timing_.reset();
        
        // === PIPELINE STAGE 1: Spatial Filtering ===
        std::vector<Point> filtered_points;
        float nearest_raw_dist;
        applySpatialFilter(msg, filtered_points, nearest_raw_dist);
        
        // === PIPELINE STAGE 2: Clustering ===
        std::vector<BoundingBox> clusters;
        clusterObstacles(filtered_points, clusters);
        
        // === PIPELINE STAGE 3: Validation & Visualization ===
        float nearest_validated_dist;
        bool emergency_flag;
        processValidatedClusters(clusters, msg, nearest_validated_dist, emergency_flag);
        
        // === PUBLISH OUTPUTS ===
        std_msgs::msg::Float32 dist_msg;
        dist_msg.data = nearest_validated_dist;
        nearest_pub_->publish(dist_msg);
        
        std_msgs::msg::Bool estop_msg;
        estop_msg.data = emergency_flag;
        estop_pub_->publish(estop_msg);
        
        // === PERFORMANCE LOGGING ===
        if (enable_timing_) {
            auto t_pipeline_end = std::chrono::high_resolution_clock::now();
            timing_.total_ms = std::chrono::duration<double, std::milli>(t_pipeline_end - t_pipeline_start).count();
            
            if (scan_count_ % timing_log_interval_ == 0) {
                RCLCPP_INFO(this->get_logger(),
                    "Performance [scan #%d]: Total=%.2fms (Filter=%.2fms, Cluster=%.2fms) | "
                    "Points: %zu filtered, %zu clusters, %d validated",
                    scan_count_, timing_.total_ms, timing_.filtering_ms, timing_.clustering_ms,
                    filtered_points.size(), clusters.size(), prev_marker_count_);
            }
        }
        
        // Warning if obstacle detected
        if (nearest_validated_dist < warning_dist_) {
            RCLCPP_WARN_THROTTLE(this->get_logger(), *this->get_clock(), 500,
                "OBSTACLE @ %.2fm | %zu clusters, %d validated",
                nearest_validated_dist, clusters.size(), prev_marker_count_);
        }
    }

    // ==== MEMBER VARIABLES ====
    rclcpp::Subscription<sensor_msgs::msg::LaserScan>::SharedPtr scan_sub_;
    rclcpp::Publisher<visualization_msgs::msg::MarkerArray>::SharedPtr marker_pub_;
    rclcpp::Publisher<std_msgs::msg::Float32>::SharedPtr nearest_pub_;
    rclcpp::Publisher<std_msgs::msg::Bool>::SharedPtr estop_pub_;
    rclcpp::TimerBase::SharedPtr watchdog_timer_;
    rclcpp::node_interfaces::OnSetParametersCallbackHandle::SharedPtr param_cb_handle_;
};

int main(int argc, char * argv[]) {
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<LidarFilterNode>());
    rclcpp::shutdown();
    return 0;
}
