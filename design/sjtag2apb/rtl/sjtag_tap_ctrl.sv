// =============================================================================
// sjtag_tap_ctrl.sv - JTAG TAP 控制器状态机
//
// 功能：
//   实现 IEEE 1149.1 标准的 TAP 状态机，共 16 个状态。
//   在 TCK 上升沿采样 TMS，驱动状态转移。
//   支持 TRST_N 异步复位，复位后进入 TEST_LOGIC_RESET 状态。
//
// 端口：
//   tck       - JTAG 时钟（上升沿有效）
//   trst_n    - JTAG 异步复位（低有效）
//   tms       - 测试模式选择（在 TCK 上升沿采样）
//   tap_state - 当前 TAP 状态（组合输出）
//
// 注意：
//   TMS 连续 5 个 TCK 上升沿保持高电平可从任意状态进入
//   TEST_LOGIC_RESET，无需依赖 TRST_N。
// =============================================================================

module sjtag_tap_ctrl
  import sjtag2apb_pkg::*;
(
  input  logic       tck,
  input  logic       trst_n,
  input  logic       tms,
  output tap_state_e tap_state
);

  tap_state_e state_q, state_d;

  // ---------------------------------------------------------------------------
  // 次态逻辑（标准 IEEE 1149.1 状态转移表）
  // ---------------------------------------------------------------------------
  always_comb begin : tap_next_state
    case (state_q)
      // DR 扫描路径
      TAP_TEST_LOGIC_RESET : state_d = tms ? TAP_TEST_LOGIC_RESET : TAP_RUN_TEST_IDLE;
      TAP_RUN_TEST_IDLE    : state_d = tms ? TAP_SELECT_DR        : TAP_RUN_TEST_IDLE;
      TAP_SELECT_DR        : state_d = tms ? TAP_SELECT_IR        : TAP_CAPTURE_DR;
      TAP_CAPTURE_DR       : state_d = tms ? TAP_EXIT1_DR         : TAP_SHIFT_DR;
      TAP_SHIFT_DR         : state_d = tms ? TAP_EXIT1_DR         : TAP_SHIFT_DR;
      TAP_EXIT1_DR         : state_d = tms ? TAP_UPDATE_DR        : TAP_PAUSE_DR;
      TAP_PAUSE_DR         : state_d = tms ? TAP_EXIT2_DR         : TAP_PAUSE_DR;
      TAP_EXIT2_DR         : state_d = tms ? TAP_UPDATE_DR        : TAP_SHIFT_DR;
      TAP_UPDATE_DR        : state_d = tms ? TAP_SELECT_DR        : TAP_RUN_TEST_IDLE;
      // IR 扫描路径
      TAP_SELECT_IR        : state_d = tms ? TAP_TEST_LOGIC_RESET : TAP_CAPTURE_IR;
      TAP_CAPTURE_IR       : state_d = tms ? TAP_EXIT1_IR         : TAP_SHIFT_IR;
      TAP_SHIFT_IR         : state_d = tms ? TAP_EXIT1_IR         : TAP_SHIFT_IR;
      TAP_EXIT1_IR         : state_d = tms ? TAP_UPDATE_IR        : TAP_PAUSE_IR;
      TAP_PAUSE_IR         : state_d = tms ? TAP_EXIT2_IR         : TAP_PAUSE_IR;
      TAP_EXIT2_IR         : state_d = tms ? TAP_UPDATE_IR        : TAP_SHIFT_IR;
      TAP_UPDATE_IR        : state_d = tms ? TAP_SELECT_DR        : TAP_RUN_TEST_IDLE;
      default              : state_d = TAP_TEST_LOGIC_RESET;
    endcase
  end : tap_next_state

  // ---------------------------------------------------------------------------
  // 状态寄存器（TCK 上升沿更新，TRST_N 异步复位）
  // ---------------------------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin : tap_state_ff
    if (!trst_n) state_q <= TAP_TEST_LOGIC_RESET;
    else         state_q <= state_d;
  end : tap_state_ff

  assign tap_state = state_q;

endmodule : sjtag_tap_ctrl
