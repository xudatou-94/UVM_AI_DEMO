// =============================================================================
// axi_monitor_pkg.sv
// =============================================================================
package axi_monitor_pkg;

  // -------------------------------------------------------------------------
  // AXI 总线宽度参数
  // -------------------------------------------------------------------------
  parameter int AXI_ADDR_W    = 32;
  parameter int AXI_DATA_W    = 32;
  parameter int AXI_ID_W      = 8;

  // -------------------------------------------------------------------------
  // PMU 参数
  // -------------------------------------------------------------------------
  parameter int PMU_CNT_W     = 32;

  // -------------------------------------------------------------------------
  // Trace 参数
  // -------------------------------------------------------------------------
  parameter int TRACE_DEPTH   = 32;
  parameter int TRACE_PTR_W   = $clog2(TRACE_DEPTH);   // 5
  parameter int OUTSTANDING_W = 8;

  // -------------------------------------------------------------------------
  // 多通道参数
  // -------------------------------------------------------------------------
  parameter int N_CH    = 4;                  // 监控通道数
  parameter int N_CH_W  = $clog2(N_CH);       // 通道选择位宽 = 2

  // -------------------------------------------------------------------------
  // Trace 条件字段选择
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    TRACE_FIELD_AW_ADDR = 3'd0,
    TRACE_FIELD_AR_ADDR = 3'd1,
    TRACE_FIELD_W_DATA  = 3'd2,
    TRACE_FIELD_R_DATA  = 3'd3,
    TRACE_FIELD_AW_ID   = 3'd4,
    TRACE_FIELD_AR_ID   = 3'd5,
    TRACE_FIELD_BURST   = 3'd6
  } trace_field_e;

  // -------------------------------------------------------------------------
  // Trace 条件比较运算符
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    TRACE_OP_EQ  = 3'd0,
    TRACE_OP_NEQ = 3'd1,
    TRACE_OP_GT  = 3'd2,
    TRACE_OP_LT  = 3'd3,
    TRACE_OP_GTE = 3'd4,
    TRACE_OP_LTE = 3'd5
  } trace_op_e;

  // -------------------------------------------------------------------------
  // SRAM 记录条目结构（addr + data + id + burst + outstanding）
  // -------------------------------------------------------------------------
  typedef struct packed {
    logic [AXI_ADDR_W-1:0]    addr;
    logic [AXI_DATA_W-1:0]    data;
    logic [AXI_ID_W-1:0]      id;
    logic [1:0]                burst;
    logic [OUTSTANDING_W-1:0]  outstanding;
  } trace_entry_t;

  // -------------------------------------------------------------------------
  // 通道事件结构体：CDC 模块输出（dst_clk 域）
  //
  // *_event 为单周期脉冲；其余字段在 *_event 为高的同一拍有效，
  // 其后保持上次值直到下一次事件。
  // -------------------------------------------------------------------------
  typedef struct packed {
    // AW 通道
    logic                   aw_event;
    logic [AXI_ADDR_W-1:0]  aw_addr;
    logic [AXI_ID_W-1:0]    aw_id;
    logic [1:0]              aw_burst;
    // W 通道
    logic                   w_event;
    logic [AXI_DATA_W-1:0]  w_data;
    // B 通道
    logic                   b_event;
    // AR 通道
    logic                   ar_event;
    logic [AXI_ADDR_W-1:0]  ar_addr;
    logic [AXI_ID_W-1:0]    ar_id;
    logic [1:0]              ar_burst;
    // R 通道
    logic                   r_event;
    logic [AXI_DATA_W-1:0]  r_data;
    logic [AXI_ID_W-1:0]    r_id;
  } axi_ch_events_t;

endpackage
