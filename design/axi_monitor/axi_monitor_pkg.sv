// =============================================================================
// axi_monitor_pkg.sv
// 全局参数、类型定义
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
  parameter int PMU_CNT_W     = 32;   // 各通道计数器位宽

  // -------------------------------------------------------------------------
  // Trace 参数
  // -------------------------------------------------------------------------
  parameter int TRACE_DEPTH   = 32;                    // SRAM 深度
  parameter int TRACE_PTR_W   = $clog2(TRACE_DEPTH);  // 地址指针位宽 = 5
  parameter int OUTSTANDING_W = 8;                     // outstanding 计数位宽

  // -------------------------------------------------------------------------
  // Trace 条件字段选择
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    TRACE_FIELD_AW_ADDR = 3'd0,   // 写地址
    TRACE_FIELD_AR_ADDR = 3'd1,   // 读地址
    TRACE_FIELD_W_DATA  = 3'd2,   // 写数据
    TRACE_FIELD_R_DATA  = 3'd3,   // 读数据
    TRACE_FIELD_AW_ID   = 3'd4,   // 写 ID
    TRACE_FIELD_AR_ID   = 3'd5,   // 读 ID
    TRACE_FIELD_BURST   = 3'd6    // Burst 类型
  } trace_field_e;

  // -------------------------------------------------------------------------
  // Trace 条件比较运算符
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    TRACE_OP_EQ  = 3'd0,   // ==
    TRACE_OP_NEQ = 3'd1,   // !=
    TRACE_OP_GT  = 3'd2,   // >
    TRACE_OP_LT  = 3'd3,   // <
    TRACE_OP_GTE = 3'd4,   // >=
    TRACE_OP_LTE = 3'd5    // <=
  } trace_op_e;

  // -------------------------------------------------------------------------
  // SRAM 记录条目结构
  // 每条记录：地址 + 数据 + ID + burst 类型 + outstanding 计数
  // -------------------------------------------------------------------------
  typedef struct packed {
    logic [AXI_ADDR_W-1:0]    addr;         // 32 bit
    logic [AXI_DATA_W-1:0]    data;         // 32 bit
    logic [AXI_ID_W-1:0]      id;           //  8 bit
    logic [1:0]                burst;        //  2 bit
    logic [OUTSTANDING_W-1:0]  outstanding;  //  8 bit
  } trace_entry_t;  // total = 82 bit

endpackage
