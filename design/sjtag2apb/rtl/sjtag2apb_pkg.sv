// =============================================================================
// sjtag2apb_pkg.sv - SJTAG 转 APB 桥公共参数与类型定义包
//
// 说明：
//   本包定义了 TAP 状态机状态编码、IR 指令编码及全局参数，
//   所有相关模块均需 import 此包。
//
// TAP 状态机遵循 IEEE 1149.1 标准，共 16 个状态。
// IR 指令编码（4-bit）：
//   BYPASS     (4'hF) - 旁路模式，复位默认指令
//   IDCODE     (4'h1) - 读取设备 ID（32bit，只读）
//   APB_ACCESS (4'h2) - APB 总线访问（读/写）
//
// APB_ACCESS DR 格式（65bit，LSB first 移位）：
//   [64]    = RW     (1=写，0=读)
//   [63:32] = PADDR  (32bit APB 地址)
//   [31:0]  = DATA   (写数据输入 / 读数据输出)
// =============================================================================

package sjtag2apb_pkg;

  // ---------------------------------------------------------------------------
  // TAP 状态机状态编码（IEEE 1149.1，4bit）
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    TAP_TEST_LOGIC_RESET = 4'h0,
    TAP_RUN_TEST_IDLE    = 4'h1,
    TAP_SELECT_DR        = 4'h2,
    TAP_CAPTURE_DR       = 4'h3,
    TAP_SHIFT_DR         = 4'h4,
    TAP_EXIT1_DR         = 4'h5,
    TAP_PAUSE_DR         = 4'h6,
    TAP_EXIT2_DR         = 4'h7,
    TAP_UPDATE_DR        = 4'h8,
    TAP_SELECT_IR        = 4'h9,
    TAP_CAPTURE_IR       = 4'hA,
    TAP_SHIFT_IR         = 4'hB,
    TAP_EXIT1_IR         = 4'hC,
    TAP_PAUSE_IR         = 4'hD,
    TAP_EXIT2_IR         = 4'hE,
    TAP_UPDATE_IR        = 4'hF
  } tap_state_e;

  // ---------------------------------------------------------------------------
  // IR 指令编码（4bit）
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    INSTR_IDCODE     = 4'h1,  // 读取设备 ID
    INSTR_APB_ACCESS = 4'h2,  // APB 总线访问
    INSTR_BYPASS     = 4'hF   // 旁路（复位默认）
  } tap_instr_e;

  // ---------------------------------------------------------------------------
  // 全局参数
  // ---------------------------------------------------------------------------
  parameter int IR_LEN       = 4;               // IR 指令寄存器位宽
  parameter int APB_ADDR_W   = 32;              // APB 地址位宽
  parameter int APB_DATA_W   = 32;              // APB 数据位宽
  // APB_ACCESS DR 总位宽：1(RW) + 32(ADDR) + 32(DATA) = 65
  parameter int DR_APB_LEN   = 1 + APB_ADDR_W + APB_DATA_W;

  // 设备 IDCODE（JEDEC 格式，bit0 固定为 1）
  parameter logic [31:0] IDCODE_VAL = 32'h5A7B_0001;

endpackage : sjtag2apb_pkg
