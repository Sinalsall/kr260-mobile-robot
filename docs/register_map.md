# Register Map — AXI4-Lite (lidar_hw_filter)

All registers are 32-bit, accessed via single AXI4-Lite bundle `CTRL`.

| Offset | Register | Type | Function |
|:------:|----------|------|----------|
| 0x00 | AP_CTRL | uint32 | Control: bit 0 = ap_start, bit 1 = ap_done |
| 0x04 | GIE | uint32 | Global Interrupt Enable |
| 0x08 | IER | uint32 | IP Interrupt Enable |
| 0x0C | ISR | uint32 | IP Interrupt Status |
| 0x10 | angle_min | float | Start angle of scan (radians) |
| 0x18 | angle_increment | float | Angular resolution per point (radians) |
| 0x20 | filter_range_min | float | Minimum valid range (meters) |
| 0x28 | filter_range_max | float | Maximum valid range (meters) |
| 0x30 | roi_x_min | float | ROI near boundary (meters) |
| 0x38 | roi_x_max | float | ROI far boundary (meters) |
| 0x40 | roi_y_base | float | Half-width at x=0 (meters) |
| 0x48 | roi_y_expansion_rate | float | Width increase per meter |
| 0x50 | landmark_range_min | float | Minimum range for landmarks (meters) |
| 0x58 | landmark_range_max | float | Maximum range for landmarks (meters) |
| 0x60 | scan_size | int | Number of points per scan frame |

## Access from PS (C++)

```cpp
// Write parameters (float -> uint32 bit conversion)
ip_ptr_[0x10 / 4] = float_to_uint(angle_min);
ip_ptr_[0x18 / 4] = float_to_uint(angle_increment);
// ...

// Start IP
ip_ptr_[0] = 1;  // ap_start
```

## Note

- Offset is divided by 4 when accessing via `uint32_t*` pointer
- Float values require bit-level conversion (memcpy or union) for register write
- Registers must be written BEFORE `ap_start` is triggered
- `ap_done` (bit 1) is COR (Clear on Read) — use status register for completion polling

## ROI Trapezoid Parameters

```
roi_width = roi_y_base + x * roi_y_expansion_rate
```

Default values:
- roi_y_base = 0.2 m (total corridor width = 0.4 m at robot)
- roi_y_expansion_rate = 0.1 m/m (corridor widens by 0.1 m per side per meter forward)

At x=0.3 m: width = 2 * (0.2 + 0.3*0.1) = 0.46 m
At x=1.0 m: width = 2 * (0.2 + 1.0*0.1) = 0.60 m
