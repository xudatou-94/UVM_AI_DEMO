// ============================================================
// OTBN Environment Package
// ============================================================
package otbn_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import tlul_pkg::*;
  import otbn_reg_pkg::*;
  import otbn_pkg::*;
  import otbn_tl_pkg::*;

  `include "otbn_env_cfg.sv"
  `include "otbn_scoreboard.sv"
  `include "otbn_env.sv"

endpackage
