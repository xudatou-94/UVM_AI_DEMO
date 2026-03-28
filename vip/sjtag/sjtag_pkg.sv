// =============================================================================
// sjtag_pkg.sv - SJTAG VIP 顶层包
//
// 将 SJTAG VIP 所有类封装为一个 package，避免命名冲突，
// 简化上层 testbench 的文件依赖管理。
//
// 使用方法：
//   在 testbench 中 `import sjtag_pkg::*;` 即可使用全部 VIP 类。
// =============================================================================

package sjtag_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // 按依赖顺序引入 VIP 源文件
  `include "sjtag_seq_item.sv"
  `include "sjtag_agent_cfg.sv"
  `include "sjtag_sequencer.sv"
  `include "sjtag_driver.sv"
  `include "sjtag_monitor.sv"
  `include "sjtag_agent.sv"
  `include "sjtag_base_seq.sv"

endpackage : sjtag_pkg
