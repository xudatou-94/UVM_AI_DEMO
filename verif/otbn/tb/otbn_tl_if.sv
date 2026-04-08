// ============================================================
// OTBN TL-UL Virtual Interface
// ============================================================
interface otbn_tl_if (
  input logic clk,
  input logic rst_n
);
  import tlul_pkg::*;

  // Host-to-device: driven by TB driver
  tl_h2d_t h2d;
  // Device-to-host: driven by DUT
  tl_d2h_t d2h;

  // Clocking block for driver
  clocking driver_cb @(posedge clk);
    default input #1ns output #1ns;
    output h2d;
    input  d2h;
  endclocking

  // Clocking block for monitor
  clocking monitor_cb @(posedge clk);
    default input #1ns;
    input h2d;
    input d2h;
  endclocking

endinterface : otbn_tl_if
