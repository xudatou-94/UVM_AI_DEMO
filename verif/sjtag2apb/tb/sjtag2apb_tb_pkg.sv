// =============================================================================
// sjtag2apb_tb_pkg.sv - sjtag2apb 验证环境顶层包
//
// 按依赖顺序引入所有 TB 组件和激励文件。
// 在 tb_top.sv 中通过 `import sjtag2apb_tb_pkg::*` 使用。
//
// 依赖：uvm_pkg, sjtag_pkg, apb_pkg（须在本包之前编译）
// =============================================================================

package sjtag2apb_tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import sjtag_pkg::*;
  import apb_pkg::*;

  // --------------------------------------------------------------------------
  // 基础设施层（按依赖顺序：无引用关系的先，有引用关系的后）
  // --------------------------------------------------------------------------
  `include "sjtag2apb_scoreboard.sv"         // 记分板（依赖 apb_seq_item）
  `include "sjtag2apb_coverage.sv"           // 覆盖率收集器（依赖 sjtag/apb seq_item）
  `include "sjtag2apb_env.sv"                // 验证环境（依赖 apb_slave_resp_seq from VIP）

  // --------------------------------------------------------------------------
  // 测试基类（依赖 env）
  // --------------------------------------------------------------------------
  `include "sjtag2apb_base_test.sv"

  // --------------------------------------------------------------------------
  // Sequence 基类（依赖 sjtag_base_seq 和 env）
  // --------------------------------------------------------------------------
  `include "seq/sjtag2apb_tb_base_seq.sv"

  // --------------------------------------------------------------------------
  // 各测试 Sequence（依赖 tb_base_seq）
  // --------------------------------------------------------------------------
  `include "seq/sjtag2apb_tap_hard_reset_seq.sv"
  `include "seq/sjtag2apb_tap_soft_reset_seq.sv"
  `include "seq/sjtag2apb_idcode_read_seq.sv"
  `include "seq/sjtag2apb_bypass_seq.sv"
  `include "seq/sjtag2apb_apb_write_basic_seq.sv"
  `include "seq/sjtag2apb_apb_write_burst_seq.sv"
  `include "seq/sjtag2apb_apb_read_basic_seq.sv"
  `include "seq/sjtag2apb_apb_read_after_write_seq.sv"
  `include "seq/sjtag2apb_apb_wait_state_seq.sv"
  `include "seq/sjtag2apb_apb_slverr_seq.sv"
  `include "seq/sjtag2apb_cdc_freq_ratio_seq.sv"
  `include "seq/sjtag2apb_cdc_back2back_seq.sv"
  `include "seq/sjtag2apb_random_regression_seq.sv"

endpackage : sjtag2apb_tb_pkg
