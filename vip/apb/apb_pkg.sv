// =============================================================================
// apb_pkg.sv - APB VIP 顶层包
//
// 将 APB VIP 所有类封装为一个 package，避免命名冲突，
// 简化上层 testbench 的文件依赖管理。
//
// 使用方法：
//   在 testbench 中 `import apb_pkg::*;` 即可使用全部 VIP 类。
//
// 注：apb_if.sv 为接口（interface），须在 package 外独立编译，
//     不在此 package 中 `include。
// =============================================================================

package apb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // 按依赖顺序引入 VIP 源文件
  `include "apb_seq_item.sv"
  `include "apb_agent_cfg.sv"
  `include "apb_sequencer.sv"
  `include "apb_master_driver.sv"
  `include "apb_slave_driver.sv"
  `include "apb_monitor.sv"
  `include "apb_agent.sv"
  `include "apb_base_seq.sv"

endpackage : apb_pkg
