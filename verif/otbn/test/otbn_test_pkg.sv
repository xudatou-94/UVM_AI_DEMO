// ============================================================
// OTBN Test Package
// ============================================================
package otbn_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import otbn_env_pkg::*;
  import otbn_tl_pkg::*;

  `include "otbn_base_test.sv"
  `include "otbn_smoke_test.sv"
  `include "otbn_dmem_rw_test.sv"

endpackage
