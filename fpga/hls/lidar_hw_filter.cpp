#include "ap_axi_sdata.h"
#include "hls_stream.h"
#include "hls_math.h"

// Lebar Jalur Data
typedef ap_axiu<32, 0, 0, 0> axis_in_t; // 32-bit
typedef ap_axiu<128, 0, 0, 0> axis_out_t; //128-bit : float x, float y, dan integer label

union FloatInt {
    float f;
    unsigned int i;
};

void lidar_hw_filter(
    hls::stream<axis_in_t>& in_stream,
    hls::stream<axis_out_t>& out_stream,
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
    int scan_size
) {
// Pemetaan port AXI4-Stream. Terhubung ke AXI DMA
#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream

// Pemetaan variable sebagai register AXI4-Lite memori. PS menulis parameter ROS2 ke register ini. 
#pragma HLS INTERFACE s_axilite port=angle_min bundle=CTRL
#pragma HLS INTERFACE s_axilite port=angle_increment bundle=CTRL
#pragma HLS INTERFACE s_axilite port=filter_range_min bundle=CTRL
#pragma HLS INTERFACE s_axilite port=filter_range_max bundle=CTRL
#pragma HLS INTERFACE s_axilite port=roi_x_min bundle=CTRL
#pragma HLS INTERFACE s_axilite port=roi_x_max bundle=CTRL
#pragma HLS INTERFACE s_axilite port=roi_y_base bundle=CTRL
#pragma HLS INTERFACE s_axilite port=roi_y_expansion_rate bundle=CTRL
#pragma HLS INTERFACE s_axilite port=landmark_range_min bundle=CTRL
#pragma HLS INTERFACE s_axilite port=landmark_range_max bundle=CTRL
#pragma HLS INTERFACE s_axilite port=scan_size bundle=CTRL
#pragma HLS INTERFACE s_axilite port=return bundle=CTRL

    FloatInt fi_range, fi_x, fi_y;
    axis_in_t pkt_in;
    axis_out_t pkt_out;

    for (int i = 0; i < scan_size; i++) {
#pragma HLS PIPELINE II=1 // 1 clock cycle, 1 titik lidar
        in_stream.read(pkt_in);
        fi_range.i = pkt_in.data;
        float r = fi_range.f;

        if (r >= filter_range_min && r <= filter_range_max) {
            float theta = angle_min + i * angle_increment;
            float x = r * hls::cos(theta);
            float y = r * hls::sin(theta);

            int label = 0;
            float abs_y = y < 0 ? -y : y;
            float roi_width = roi_y_base + x * roi_y_expansion_rate;

            if (x >= roi_x_min && x <= roi_x_max && abs_y <= roi_width) {
                label = 1;
            } else if (r >= landmark_range_min && r <= landmark_range_max) {
                label = 2;
            }

            if (label != 0) {
                fi_x.f = x;
                fi_y.f = y;
                
                ap_uint<128> out_data = 0;
                out_data.range(31, 0) = fi_x.i;
                out_data.range(63, 32) = fi_y.i;
                out_data.range(95, 64) = label;
                out_data.range(127, 96) = 0;

                pkt_out.data = out_data;
                pkt_out.keep = -1;
                pkt_out.strb = -1;
                pkt_out.last = 0;
                out_stream.write(pkt_out);
            }
        }
    }

    ap_uint<128> eof_data = 0;
    eof_data.range(95, 64) = 99;
    pkt_out.data = eof_data;
    pkt_out.keep = -1;
    pkt_out.strb = -1;
    pkt_out.last = 1;
    out_stream.write(pkt_out);
}
