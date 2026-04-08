// ============================================================
// OTBN TL-UL Agent Package
// ============================================================
package otbn_tl_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import tlul_pkg::*;

  `include "otbn_tl_seq_item.sv"
  `include "otbn_tl_agent_cfg.sv"
  `include "otbn_tl_driver.sv"
  `include "otbn_tl_monitor.sv"
  `include "otbn_tl_agent.sv"

endpackage
