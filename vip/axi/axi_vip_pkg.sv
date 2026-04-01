// =============================================================================
// axi_vip_pkg.sv  AXI4 VIP 顶层 Package
//
// 使用方式：
//   `include "uvm_macros.svh"
//   import uvm_pkg::*;
//   import axi_vip_pkg::*;
// =============================================================================
package axi_vip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_pkg::*;

  `include "axi_seq_item.sv"
  `include "axi_agent_cfg.sv"
  `include "axi_sequencer.sv"
  `include "axi_master_driver.sv"
  `include "axi_slave_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_agent.sv"
  `include "axi_base_seq.sv"

endpackage
