#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/laser_scan.hpp"
#include "sensor_msgs/msg/point_cloud2.hpp"
#include "sensor_msgs/point_cloud2_iterator.hpp"
#include "visualization_msgs/msg/marker_array.hpp"
#include "std_msgs/msg/float32.hpp"
#include "std_msgs/msg/bool.hpp"
#include "lidar_spatial_filter/msg/roi_classification.hpp"
#include <cmath>
#include <vector>
#include <algorithm>
#include <limits>
#include <chrono>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstring>
#include <string>
#include <fstream>

using std::placeholders::_1;

struct PipelineTiming {
    double filtering_ms = 0.0;
    double classification_ms = 0.0;
    double clustering_ms = 0.0;
    double total_ms = 0.0;
    
    void reset() {
        filtering_ms = 0.0;
        classification_ms = 0.0;
        clustering_ms = 0.0;
        total_ms = 0.0;
    }
};

struct TimingStats {
    int count = 0;

    double total_sum = 0.0;
    double total_min = std::numeric_limits<double>::infinity();
    double total_max = 0.0;

    double filtering_sum = 0.0;
    double filtering_min = std::numeric_limits<double>::infinity();
    double filtering_max = 0.0;

    double classification_sum = 0.0;
    double classification_min = std::numeric_limits<double>::infinity();
    double classification_max = 0.0;

    double clustering_sum = 0.0;
    double clustering_min = std::numeric_limits<double>::infinity();
    double clustering_max = 0.0;

    void update(const PipelineTiming& t) {
        count++;

        total_sum += t.total_ms;
        total_min = std::min(total_min, t.total_ms);
        total_max = std::max(total_max, t.total_ms);

        filtering_sum += t.filtering_ms;
        filtering_min = std::min(filtering_min, t.filtering_ms);
        filtering_max = std::max(filtering_max, t.filtering_ms);

        classification_sum += t.classification_ms;
        classification_min = std::min(classification_min, t.classification_ms);
        classification_max = std::max(classification_max, t.classification_ms);

        clustering_sum += t.clustering_ms;
        clustering_min = std::min(clustering_min, t.clustering_ms);
        clustering_max = std::max(clustering_max, t.clustering_ms);
    }
};

struct Point { 
    float x, y; 
    uint8_t label;
};

struct BoundingBox {
    float x_min, x_max, y_min, y_max;
    int point_count;
};

class LidarHardwareBridge {
private:
    volatile uint32_t* dma_ptr_;
    volatile uint32_t* ip_ptr_;
    volatile uint32_t* udmabuf_ptr_;
    uint64_t phys_addr_;

    uint32_t float_to_uint(float f) {
        uint32_t i;
        std::memcpy(&i, &f, sizeof(float));
        return i;
    }

    float uint_to_float(uint32_t i) {
        float f;
        std::memcpy(&f, &i, sizeof(float));
        return f;
    }

    std::string get_uio_path(const std::string& target_name) {
        for (int i = 0; i < 10; i++) {
            std::string path = "/sys/class/uio/uio" + std::to_string(i) + "/name";
            std::ifstream file(path);
            if (file.is_open()) {
                std::string name;
                std::getline(file, name);
                if (name.find(target_name) != std::string::npos) {
                    return "/dev/uio" + std::to_string(i);
                }
            }
        }
        return "";
    }

public:
    LidarHardwareBridge() {
        std::string dma_uio = get_uio_path("dma");
        std::string ip_uio = get_uio_path("lidar");
        
        if (dma_uio.empty()) dma_uio = "/dev/uio0";
        if (ip_uio.empty()) ip_uio = "/dev/uio1";

        int fd_dma = open(dma_uio.c_str(), O_RDWR | O_SYNC);
        if (fd_dma < 0) { printf("\n[FATAL] Gagal buka %s\n", dma_uio.c_str()); exit(1); }

        int fd_ip = open(ip_uio.c_str(), O_RDWR | O_SYNC);
        if (fd_ip < 0) { printf("\n[FATAL] Gagal buka %s\n", ip_uio.c_str()); exit(1); }

        int fd_udmabuf = open("/dev/udmabuf0", O_RDWR | O_SYNC);
        if (fd_udmabuf < 0) { printf("\n[FATAL] Gagal buka /dev/udmabuf0\n"); exit(1); }

        dma_ptr_ = (volatile uint32_t*)mmap(NULL, 0x10000, PROT_READ | PROT_WRITE, MAP_SHARED, fd_dma, 0);
        ip_ptr_ = (volatile uint32_t*)mmap(NULL, 0x10000, PROT_READ | PROT_WRITE, MAP_SHARED, fd_ip, 0);
        udmabuf_ptr_ = (volatile uint32_t*)mmap(NULL, 0x800000, PROT_READ | PROT_WRITE, MAP_SHARED, fd_udmabuf, 0);

        if (dma_ptr_ == MAP_FAILED) { printf("\n[FATAL] mmap DMA gagal\n"); exit(1); }
        if (ip_ptr_ == MAP_FAILED) { printf("\n[FATAL] mmap IP HLS gagal\n"); exit(1); }
        if (udmabuf_ptr_ == MAP_FAILED) { printf("\n[FATAL] mmap udmabuf0 gagal\n"); exit(1); }

        int fd_phys = open("/sys/class/u-dma-buf/udmabuf0/phys_addr", O_RDONLY);
        if (fd_phys < 0) { printf("\n[FATAL] Gagal baca phys_addr\n"); exit(1); }
        char buf[64] = {0};
        read(fd_phys, buf, 64);
        phys_addr_ = std::strtoull(buf, NULL, 16);
        close(fd_phys);
    }

    ~LidarHardwareBridge() {
        munmap((void*)dma_ptr_, 0x10000);
        munmap((void*)ip_ptr_, 0x10000);
        munmap((void*)udmabuf_ptr_, 0x800000);
    }

    void process_scan(
        const std::vector<float>& ranges,
        float angle_min,
        float angle_increment,
        float filter_range_min,
        float filter_range_max,
        float roi_x_min,
        float roi_x_max,
        float roi_y_base,
        float roi_y_expansion_rate,
        float landmark_range_min,
        float landmark_range_max,
        std::vector<Point>& classified_points,
        std::vector<Point>& obstacle_points,
        std::vector<Point>& landmark_points,
        float& nearest_raw_dist)
    {
        if (ranges.empty()) {
            return;
        }

        classified_points.clear();
        obstacle_points.clear();
        landmark_points.clear();
        nearest_raw_dist = std::numeric_limits<float>::infinity();

        int scan_size = ranges.size();
        uint32_t tx_bytes = scan_size * sizeof(float);
        uint32_t rx_bytes = (scan_size + 1) * 16;

        if (rx_bytes > 67108863) {
            printf("\n[FATAL ERROR] RX Length %u bytes exceeds Vivado 26-bit DMA limit!\n", rx_bytes);
            return;
        }

        std::memcpy((void*)udmabuf_ptr_, ranges.data(), tx_bytes);

        uint32_t tx_phys_addr = phys_addr_;
        uint32_t rx_phys_addr = phys_addr_ + 0x400000;

        ip_ptr_[0x10 / 4] = float_to_uint(angle_min);
        ip_ptr_[0x18 / 4] = float_to_uint(angle_increment);
        ip_ptr_[0x20 / 4] = float_to_uint(filter_range_min);
        ip_ptr_[0x28 / 4] = float_to_uint(filter_range_max);
        ip_ptr_[0x30 / 4] = float_to_uint(roi_x_min);
        ip_ptr_[0x38 / 4] = float_to_uint(roi_x_max);
        ip_ptr_[0x40 / 4] = float_to_uint(roi_y_base);
        ip_ptr_[0x48 / 4] = float_to_uint(roi_y_expansion_rate);
        ip_ptr_[0x50 / 4] = float_to_uint(landmark_range_min);
        ip_ptr_[0x58 / 4] = float_to_uint(landmark_range_max);
        ip_ptr_[0x60 / 4] = scan_size;

        dma_ptr_[0x30 / 4] = 4;
        while (dma_ptr_[0x30 / 4] & 4);
        dma_ptr_[0x00 / 4] = 4;
        while (dma_ptr_[0x00 / 4] & 4);

        dma_ptr_[0x30 / 4] = 1;
        dma_ptr_[0x48 / 4] = rx_phys_addr;
        dma_ptr_[0x58 / 4] = rx_bytes;

        ip_ptr_[0] = 1;

        dma_ptr_[0x00 / 4] = 1;
        dma_ptr_[0x18 / 4] = tx_phys_addr;
        dma_ptr_[0x28 / 4] = tx_bytes;

        int timeout = 0;
        while (!(dma_ptr_[0x34 / 4] & (1 << 1)) && !(dma_ptr_[0x34 / 4] & (1 << 12))) {
            usleep(100);
            timeout++;
            if (timeout > 10000) {
                printf("\n[HW ERROR] DMA Timeout!\n");
                printf("  TX Status : 0x%08X\n", dma_ptr_[0x04 / 4]);
                printf("  RX Status : 0x%08X\n", dma_ptr_[0x34 / 4]);
                printf("  IP Status : 0x%08X\n", ip_ptr_[0]);
                break;
            }
        }

        volatile uint32_t* rx_buffer = udmabuf_ptr_ + (0x400000 / 4);
        
        for (int i = 0; i <= scan_size; i++) {
            uint32_t x_bits = rx_buffer[i * 4 + 0];
            uint32_t y_bits = rx_buffer[i * 4 + 1];
            uint32_t label  = rx_buffer[i * 4 + 2];

            if (label == 99) {
                break;
            }

            if (label != 0) {
                Point p;
                p.x = uint_to_float(x_bits);
                p.y = uint_to_float(y_bits);
                p.label = static_cast<uint8_t>(label);

                classified_points.push_back(p);

                if (p.label == 1) {
                    obstacle_points.push_back(p);
                    float r = std::sqrt(p.x * p.x + p.y * p.y);
                    nearest_raw_dist = std::min(nearest_raw_dist, r);
                } else if (p.label == 2) {
                    landmark_points.push_back(p); 
                    
                    // Landmark dalam radius 0.7m dianggap sebagai Obstacle
                    float r = std::sqrt(p.x * p.x + p.y * p.y);
                    if (r <= 0.7f) {
                        Point p_as_obs = p;
                        p_as_obs.label = 1; 
                        obstacle_points.push_back(p_as_obs);
                        nearest_raw_dist = std::min(nearest_raw_dist, r);
                    }
                }
            }
        }
    }
};

class LidarPlNode : public rclcpp::Node {
public:
    LidarPlNode() : Node("lidar_pl_node"), sequence_id_(0) {
        this->declare_parameter("filter.range_min", 0.15);
        this->declare_parameter("filter.range_max", 3.0);
        this->declare_parameter("roi.x_min", 0.15);
        this->declare_parameter("roi.x_max", 1.0);
        this->declare_parameter("roi.y_base", 0.2);
        this->declare_parameter("roi.y_expansion_rate", 0.1);
        this->declare_parameter("roi.landmark_range_min", 0.2);
        this->declare_parameter("roi.landmark_range_max", 3.0);
        this->declare_parameter("cluster.tolerance", 0.05);
        this->declare_parameter("cluster.min_obj_size", 0.06);
        this->declare_parameter("cluster.min_points", 3);
        this->declare_parameter("tracked_object.max_obj_size", 0.40);
        this->declare_parameter("tracked_object.max_points", 80);
        this->declare_parameter("safety.emergency_distance", 0.16);
        this->declare_parameter("safety.warning_distance", 0.50);
        this->declare_parameter("system.scan_timeout_sec", 0.5);
        this->declare_parameter("system.scan_topic", std::string("/scan"));
        this->declare_parameter("system.enable_timing", true);
        this->declare_parameter("system.timing_log_interval", 50);

        loadParameters();

        hw_bridge_ = std::make_shared<LidarHardwareBridge>();

        auto qos = rclcpp::SensorDataQoS();
        scan_sub_ = this->create_subscription<sensor_msgs::msg::LaserScan>(
            scan_topic_, qos, std::bind(&LidarPlNode::scan_callback, this, _1));

        marker_pub_ = this->create_publisher<visualization_msgs::msg::MarkerArray>("/obstacle_boxes", 10);
        nearest_pub_ = this->create_publisher<std_msgs::msg::Float32>("/obstacle_nearest_distance", 10);
        outside_roi_object_dist_pub_ = this->create_publisher<std_msgs::msg::Float32>("/navigation/outside_roi_object_distance", 10);
        estop_pub_ = this->create_publisher<std_msgs::msg::Bool>("/emergency_stop", 10);
        roi_classification_pub_ = this->create_publisher<lidar_spatial_filter::msg::ROIClassification>(
            "/navigation/roi_classification", 10);
        obstacle_points_pub_ = this->create_publisher<sensor_msgs::msg::PointCloud2>(
            "/navigation/obstacle_points", 10);
        // Publisher landmark dihapus sesuai permintaan
        roi_viz_pub_ = this->create_publisher<visualization_msgs::msg::MarkerArray>(
            "/navigation/roi_boundary", 10);

        last_scan_time_ = this->now();
        watchdog_timer_ = this->create_wall_timer(
            std::chrono::milliseconds(static_cast<int>(scan_timeout_ * 1000)),
            std::bind(&LidarPlNode::watchdog_callback, this));

        param_cb_handle_ = this->add_on_set_parameters_callback(
            std::bind(&LidarPlNode::on_parameter_change, this, _1));
    }

private:
    std::shared_ptr<LidarHardwareBridge> hw_bridge_;

    double filter_range_min_, filter_range_max_;
    double roi_x_min_, roi_x_max_;
    double roi_y_base_, roi_y_expansion_rate_;
    double landmark_range_min_, landmark_range_max_;
    double cluster_tol_;
    double min_obj_size_;
    int min_obj_points_;
    double tracked_max_obj_size_;
    int tracked_max_points_;
    double emergency_dist_, warning_dist_;
    double scan_timeout_;
    std::string scan_topic_;
    bool enable_timing_;
    int timing_log_interval_;

    rclcpp::Time last_scan_time_;
    int prev_marker_count_ = 0;
    uint32_t sequence_id_;
    PipelineTiming timing_;
    TimingStats timing_stats_;
    int scan_count_ = 0;

    void loadParameters() {
        filter_range_min_ = this->get_parameter("filter.range_min").as_double();
        filter_range_max_ = this->get_parameter("filter.range_max").as_double();
        roi_x_min_ = this->get_parameter("roi.x_min").as_double();
        roi_x_max_ = this->get_parameter("roi.x_max").as_double();
        roi_y_base_ = this->get_parameter("roi.y_base").as_double();
        roi_y_expansion_rate_ = this->get_parameter("roi.y_expansion_rate").as_double();
        landmark_range_min_ = this->get_parameter("roi.landmark_range_min").as_double();
        landmark_range_max_ = this->get_parameter("roi.landmark_range_max").as_double();
        cluster_tol_ = this->get_parameter("cluster.tolerance").as_double();
        min_obj_size_ = this->get_parameter("cluster.min_obj_size").as_double();
        tracked_max_obj_size_ = this->get_parameter("tracked_object.max_obj_size").as_double();
        min_obj_points_ = this->get_parameter("cluster.min_points").as_int();
        tracked_max_points_ = this->get_parameter("tracked_object.max_points").as_int();
        emergency_dist_ = this->get_parameter("safety.emergency_distance").as_double();
        warning_dist_ = this->get_parameter("safety.warning_distance").as_double();
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
            if (name == "filter.range_min") filter_range_min_ = p.as_double();
            else if (name == "filter.range_max") filter_range_max_ = p.as_double();
            else if (name == "roi.x_min") roi_x_min_ = p.as_double();
            else if (name == "roi.x_max") roi_x_max_ = p.as_double();
            else if (name == "roi.y_base") roi_y_base_ = p.as_double();
            else if (name == "roi.y_expansion_rate") roi_y_expansion_rate_ = p.as_double();
            else if (name == "roi.landmark_range_min") landmark_range_min_ = p.as_double();
            else if (name == "roi.landmark_range_max") landmark_range_max_ = p.as_double();
            else if (name == "cluster.tolerance") cluster_tol_ = p.as_double();
            else if (name == "cluster.min_obj_size") min_obj_size_ = p.as_double();
            else if (name == "tracked_object.max_obj_size") tracked_max_obj_size_ = p.as_double();
            else if (name == "cluster.min_points") min_obj_points_ = p.as_int();
            else if (name == "tracked_object.max_points") tracked_max_points_ = p.as_int();
            else if (name == "safety.emergency_distance") emergency_dist_ = p.as_double();
            else if (name == "safety.warning_distance") warning_dist_ = p.as_double();
            else if (name == "system.enable_timing") enable_timing_ = p.as_bool();
            else if (name == "system.timing_log_interval") timing_log_interval_ = p.as_int();
        }
        rcl_interfaces::msg::SetParametersResult result;
        result.successful = true;
        return result;
    }

    void watchdog_callback() {
        double elapsed = (this->now() - last_scan_time_).seconds();
        if (elapsed > scan_timeout_) {
            std_msgs::msg::Bool estop;
            estop.data = true;
            estop_pub_->publish(estop);
        }
    }

    float calcROIWidth(float x) const {
        return static_cast<float>(roi_y_base_ + x * roi_y_expansion_rate_);
    }

    void publishROIClassification(
        const sensor_msgs::msg::LaserScan::SharedPtr& msg,
        const rclcpp::Time& processing_start_time,
        const std::vector<Point>& classified_points)
    {
        lidar_spatial_filter::msg::ROIClassification out;
        out.header = msg->header;
        out.sequence_id = sequence_id_;
        out.processing_start_time = processing_start_time;
        out.points.reserve(classified_points.size());
        out.labels.reserve(classified_points.size());
        out.total_points = static_cast<uint32_t>(classified_points.size());
        out.obstacle_count = 0;
        out.landmark_count = 0;
        out.ignored_count = 0;

        for (const auto& p : classified_points) {
            geometry_msgs::msg::Point gp;
            gp.x = p.x;
            gp.y = p.y;
            gp.z = 0.0;
            out.points.push_back(gp);
            out.labels.push_back(p.label);

            if (p.label == 1) out.obstacle_count++;
            else if (p.label == 2) out.landmark_count++;
            else out.ignored_count++;
        }
        roi_classification_pub_->publish(out);
    }

    void publishPointCloud(
        const sensor_msgs::msg::LaserScan::SharedPtr& msg,
        const std::vector<Point>& points,
        const rclcpp::Publisher<sensor_msgs::msg::PointCloud2>::SharedPtr& pub)
    {
        sensor_msgs::msg::PointCloud2 cloud;
        cloud.header = msg->header;
        cloud.height = 1;
        cloud.width = static_cast<uint32_t>(points.size());
        cloud.is_bigendian = false;
        cloud.is_dense = true;

        sensor_msgs::PointCloud2Modifier modifier(cloud);
        modifier.setPointCloud2FieldsByString(1, "xyz");
        modifier.resize(points.size());

        sensor_msgs::PointCloud2Iterator<float> iter_x(cloud, "x");
        sensor_msgs::PointCloud2Iterator<float> iter_y(cloud, "y");
        sensor_msgs::PointCloud2Iterator<float> iter_z(cloud, "z");

        for (const auto& p : points) {
            *iter_x = p.x;
            *iter_y = p.y;
            *iter_z = 0.0f;
            ++iter_x;
            ++iter_y;
            ++iter_z;
        }
        pub->publish(cloud);
    }

    void publishROIBoundary(const sensor_msgs::msg::LaserScan::SharedPtr& msg)
    {
        visualization_msgs::msg::MarkerArray markers;
        const float x_near = static_cast<float>(roi_x_min_);
        const float x_far = static_cast<float>(roi_x_max_);
        const float y_near = calcROIWidth(x_near);
        const float y_far = calcROIWidth(x_far);

        geometry_msgs::msg::Point p1, p2, p3, p4;
        p1.x = x_near; p1.y = y_near;  p1.z = 0.0;
        p2.x = x_far;  p2.y = y_far;   p2.z = 0.0;
        p3.x = x_far;  p3.y = -y_far;  p3.z = 0.0;
        p4.x = x_near; p4.y = -y_near; p4.z = 0.0;

        visualization_msgs::msg::Marker fill;
        fill.header = msg->header;
        fill.ns = "roi";
        fill.id = 0;
        fill.type = visualization_msgs::msg::Marker::TRIANGLE_LIST;
        fill.action = visualization_msgs::msg::Marker::ADD;
        fill.pose.orientation.w = 1.0;
        fill.scale.x = 1.0;
        fill.scale.y = 1.0;
        fill.scale.z = 1.0;
        fill.color.r = 0.0f;
        fill.color.g = 1.0f;
        fill.color.b = 0.0f;
        fill.color.a = 0.20f;
        fill.lifetime = rclcpp::Duration::from_seconds(0.5);
        fill.points = {p1, p2, p3, p1, p3, p4};
        markers.markers.push_back(fill);

        visualization_msgs::msg::Marker outline;
        outline.header = msg->header;
        outline.ns = "roi";
        outline.id = 1;
        outline.type = visualization_msgs::msg::Marker::LINE_STRIP;
        outline.action = visualization_msgs::msg::Marker::ADD;
        outline.pose.orientation.w = 1.0;
        outline.scale.x = 0.02;
        outline.color.r = 0.0f;
        outline.color.g = 1.0f;
        outline.color.b = 0.0f;
        outline.color.a = 1.0f;
        outline.lifetime = rclcpp::Duration::from_seconds(0.5);
        outline.points = {p1, p2, p3, p4, p1};
        markers.markers.push_back(outline);

        roi_viz_pub_->publish(markers);
    }

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
        
        BoundingBox current_box = {
            filtered_points[0].x, filtered_points[0].x,
            filtered_points[0].y, filtered_points[0].y, 1
        };
        
        for (size_t i = 1; i < filtered_points.size(); ++i) {
            float dx_to_center = filtered_points[i].x - (current_box.x_min + current_box.x_max) / 2.0f;
            float dy_to_center = filtered_points[i].y - (current_box.y_min + current_box.y_max) / 2.0f;
            
            float half_w = (current_box.x_max - current_box.x_min) / 2.0f;
            float half_h = (current_box.y_max - current_box.y_min) / 2.0f;
            float dx_edge = std::max(0.0f, std::abs(dx_to_center) - half_w);
            float dy_edge = std::max(0.0f, std::abs(dy_to_center) - half_h);
            
            float dist_to_box = std::sqrt(dx_edge * dx_edge + dy_edge * dy_edge);
            
            if (dist_to_box <= cluster_tol_) {
                current_box.x_min = std::min(current_box.x_min, filtered_points[i].x);
                current_box.x_max = std::max(current_box.x_max, filtered_points[i].x);
                current_box.y_min = std::min(current_box.y_min, filtered_points[i].y);
                current_box.y_max = std::max(current_box.y_max, filtered_points[i].y);
                current_box.point_count++;
            } else {
                clusters.push_back(current_box);
                current_box = {
                    filtered_points[i].x, filtered_points[i].x,
                    filtered_points[i].y, filtered_points[i].y, 1
                };
            }
        }
        clusters.push_back(current_box);
        
        if (enable_timing_) {
            auto t_end = std::chrono::high_resolution_clock::now();
            timing_.clustering_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();
        }
    }

    void processValidatedClusters(
        const std::vector<BoundingBox>& clusters,
        const sensor_msgs::msg::LaserScan::SharedPtr& msg,
        float& nearest_validated_dist,
        bool& emergency_flag)
    {
        visualization_msgs::msg::MarkerArray marker_array;
        
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
            
            if ((obj_width >= min_obj_size_ || obj_length >= min_obj_size_) &&
                 box.point_count >= min_obj_points_ && 
                 obj_width <= tracked_max_obj_size_ && 
		         obj_length <= tracked_max_obj_size_ && 
                 box.point_count <= tracked_max_points_) {
                
                float nearest_x = 0.0f;
                float nearest_y = 0.0f;

                if (0.0f < box.x_min) nearest_x = box.x_min;
                else if (0.0f > box.x_max) nearest_x = box.x_max;

                if (0.0f < box.y_min) nearest_y = box.y_min;
                else if (0.0f > box.y_max) nearest_y = box.y_max;

                float abs_dist = std::sqrt(nearest_x * nearest_x + nearest_y * nearest_y);

                nearest_validated_dist = std::min(nearest_validated_dist, abs_dist);
                
                if (abs_dist < emergency_dist_) {
                    emergency_flag = true;
                }
                
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
                
                if (abs_dist < emergency_dist_) {
                    marker.color.r = 1.0f; marker.color.g = 0.0f; marker.color.b = 0.0f;
                    marker.color.a = 0.8f;
                } else if (abs_dist < warning_dist_) {
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

    void processOutsideROIObjectClusters(
    const std::vector<BoundingBox>& clusters,
    float& nearest_outside_roi_object_dist)
    {
        nearest_outside_roi_object_dist = std::numeric_limits<float>::infinity();

        for (const auto& box : clusters) {
            float obj_width = box.y_max - box.y_min;
            float obj_length = box.x_max - box.x_min;

            if ((obj_width >= min_obj_size_ || obj_length >= min_obj_size_) &&
                box.point_count >= min_obj_points_ &&
                obj_width <= tracked_max_obj_size_ &&
                obj_length <= tracked_max_obj_size_ &&
                box.point_count <= tracked_max_points_) {

                float nearest_x = 0.0f;
                float nearest_y = 0.0f;

                if (0.0f < box.x_min) nearest_x = box.x_min;
                else if (0.0f > box.x_max) nearest_x = box.x_max;

                if (0.0f < box.y_min) nearest_y = box.y_min;
                else if (0.0f > box.y_max) nearest_y = box.y_max;

                float dist = std::sqrt(nearest_x * nearest_x + nearest_y * nearest_y);
                nearest_outside_roi_object_dist = std::min(nearest_outside_roi_object_dist, dist);
            }
        }
    }

    void scan_callback(const sensor_msgs::msg::LaserScan::SharedPtr msg) {
        auto t_pipeline_start = std::chrono::high_resolution_clock::now();
        last_scan_time_ = this->now();
        sequence_id_++;
        scan_count_++;
        timing_.reset();
        
        const rclcpp::Time processing_start_time = this->now();

        std::vector<Point> classified_points;
        std::vector<Point> obstacle_points;
        std::vector<Point> landmark_points;
        float nearest_raw_dist;

        auto t_hw_start = std::chrono::high_resolution_clock::now();
        
        hw_bridge_->process_scan(
            msg->ranges,
            msg->angle_min,
            msg->angle_increment,
            filter_range_min_,
            filter_range_max_,
            roi_x_min_,
            roi_x_max_,
            roi_y_base_,
            roi_y_expansion_rate_,
            landmark_range_min_,
            landmark_range_max_,
            classified_points,
            obstacle_points,
            landmark_points,
            nearest_raw_dist
        );

        if (enable_timing_) {
            auto t_hw_end = std::chrono::high_resolution_clock::now();
            timing_.filtering_ms = std::chrono::duration<double, std::milli>(t_hw_end - t_hw_start).count();
            timing_.classification_ms = 0.0;
        }

        publishROIClassification(msg, processing_start_time, classified_points);
        publishPointCloud(msg, obstacle_points, obstacle_points_pub_);
        // Baris publishPointCloud untuk landmark_points telah dihapus
        publishROIBoundary(msg);
        
        std::vector<BoundingBox> clusters;
        clusterObstacles(obstacle_points, clusters);

        float nearest_validated_dist;
        bool emergency_flag;
        processValidatedClusters(clusters, msg, nearest_validated_dist, emergency_flag);

        std_msgs::msg::Float32 dist_msg;
        dist_msg.data = nearest_validated_dist;
        nearest_pub_->publish(dist_msg);

        std::vector<BoundingBox> outside_roi_clusters;
        clusterObstacles(landmark_points, outside_roi_clusters);

        float nearest_outside_roi_object_dist;
        processOutsideROIObjectClusters(outside_roi_clusters, nearest_outside_roi_object_dist);

        std_msgs::msg::Float32 outside_dist_msg;
        outside_dist_msg.data = nearest_outside_roi_object_dist;
        outside_roi_object_dist_pub_->publish(outside_dist_msg);
        
        std_msgs::msg::Bool estop_msg;
        estop_msg.data = emergency_flag;
        estop_pub_->publish(estop_msg);
        
        if (enable_timing_) {
	    auto t_pipeline_end = std::chrono::high_resolution_clock::now();
	    timing_.total_ms = std::chrono::duration<double, std::milli>(t_pipeline_end - t_pipeline_start).count();

	    timing_stats_.update(timing_);

	    if (scan_count_ % timing_log_interval_ == 0) {
	        RCLCPP_INFO(this->get_logger(),
	            "Performance[scan #%d]: Total=%.2fms (HW=%.2fms, Cluster=%.2fms) | "
	            "Points: %zu processed, %zu obstacle, %zu landmark | %zu clusters, %d validated",
	            scan_count_, timing_.total_ms, timing_.filtering_ms, timing_.clustering_ms,
	            classified_points.size(), obstacle_points.size(), landmark_points.size(),
	            clusters.size(), prev_marker_count_);

	        RCLCPP_INFO(this->get_logger(),
	            "Timing Summary [%d scans]: "
	            "Total avg/min/max=%.2f/%.2f/%.2f ms | "
	            "HW avg/min/max=%.2f/%.2f/%.2f ms | "
	            "Cluster avg/min/max=%.2f/%.2f/%.2f ms",
	            timing_stats_.count,
	            timing_stats_.total_sum / timing_stats_.count,
	            timing_stats_.total_min,
	            timing_stats_.total_max,
	            timing_stats_.filtering_sum / timing_stats_.count,
	            timing_stats_.filtering_min,
	            timing_stats_.filtering_max,
	            timing_stats_.clustering_sum / timing_stats_.count,
	            timing_stats_.clustering_min,
	            timing_stats_.clustering_max);
	    }
	}

        if (nearest_validated_dist < warning_dist_) {
            RCLCPP_WARN_THROTTLE(this->get_logger(), *this->get_clock(), 500,
                "OBSTACLE @ %.2fm | %zu clusters, %d validated",
                nearest_validated_dist, clusters.size(), prev_marker_count_);
        }
    }

    rclcpp::Subscription<sensor_msgs::msg::LaserScan>::SharedPtr scan_sub_;
    rclcpp::Publisher<visualization_msgs::msg::MarkerArray>::SharedPtr marker_pub_;
    rclcpp::Publisher<std_msgs::msg::Float32>::SharedPtr nearest_pub_;
    rclcpp::Publisher<std_msgs::msg::Float32>::SharedPtr outside_roi_object_dist_pub_;
    rclcpp::Publisher<std_msgs::msg::Bool>::SharedPtr estop_pub_;
    rclcpp::Publisher<lidar_spatial_filter::msg::ROIClassification>::SharedPtr roi_classification_pub_;
    rclcpp::Publisher<sensor_msgs::msg::PointCloud2>::SharedPtr obstacle_points_pub_;
    // Deklarasi landmark_points_pub_ telah dihapus
    rclcpp::Publisher<visualization_msgs::msg::MarkerArray>::SharedPtr roi_viz_pub_;
    rclcpp::TimerBase::SharedPtr watchdog_timer_;
    rclcpp::node_interfaces::OnSetParametersCallbackHandle::SharedPtr param_cb_handle_;
};

int main(int argc, char * argv[]){
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<LidarPlNode>());
    rclcpp::shutdown();
    return 0;
}
