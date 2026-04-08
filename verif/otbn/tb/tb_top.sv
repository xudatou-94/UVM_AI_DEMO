// ============================================================
// OTBN Testbench Top
// ============================================================
`timescale 1ns/1ps

`include "prim_assert.sv"

module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import tlul_pkg::*;
  import prim_alert_pkg::*;
  import prim_mubi_pkg::*;
  import lc_ctrl_pkg::*;
  import edn_pkg::*;
  import otp_ctrl_pkg::*;
  import keymgr_pkg::*;
  import prim_ram_1p_pkg::*;
  import otbn_pkg::*;
  import otbn_reg_pkg::*;

  // ----------------------------------------------------------
  // Parameters
  // ----------------------------------------------------------
  localparam int CLK_PERIOD_NS = 10;  // 100 MHz
  localparam int NumAlerts     = otbn_reg_pkg::NumAlerts;

  // ----------------------------------------------------------
  // Clocks and resets
  // ----------------------------------------------------------
  logic clk_i;
  logic rst_ni;
  logic clk_edn_i;
  logic rst_edn_ni;
  logic clk_otp_i;
  logic rst_otp_ni;

  initial clk_i = 1'b0;
  always #(CLK_PERIOD_NS/2) clk_i = ~clk_i;

  initial clk_edn_i = 1'b0;
  always #(CLK_PERIOD_NS/2) clk_edn_i = ~clk_edn_i;

  initial clk_otp_i = 1'b0;
  always #(CLK_PERIOD_NS/2) clk_otp_i = ~clk_otp_i;

  // ----------------------------------------------------------
  // TL-UL interface (between TB driver and intg_gen)
  // ----------------------------------------------------------
  otbn_tl_if tl_if (.clk(clk_i), .rst_n(rst_ni));

  // ----------------------------------------------------------
  // Integrity generator: sits between VIF and DUT
  // Computes cmd_intg and data_intg automatically
  // ----------------------------------------------------------
  tl_h2d_t tl_h2d_intg;  // DUT input (with integrity)
  tl_d2h_t tl_d2h_dut;   // DUT output

  // Feed driver output (no integrity) through the gen module
  tlul_cmd_intg_gen u_cmd_intg_gen (
    .tl_i (tl_if.h2d),
    .tl_o (tl_h2d_intg)
  );

  // Connect DUT response back to interface
  assign tl_if.d2h = tl_d2h_dut;

  // ----------------------------------------------------------
  // Alert interface (tie-off)
  // ----------------------------------------------------------
  alert_rx_t [NumAlerts-1:0] alert_rx_i;
  alert_tx_t [NumAlerts-1:0] alert_tx_o;

  always_comb begin
    for (int i = 0; i < NumAlerts; i++) begin
      alert_rx_i[i].ack_p  = 1'b0;
      alert_rx_i[i].ack_n  = 1'b1;
      alert_rx_i[i].ping_p = 1'b0;
      alert_rx_i[i].ping_n = 1'b1;
    end
  end

  // ----------------------------------------------------------
  // LC interface (tie-off: off/default)
  // ----------------------------------------------------------
  lc_tx_t lc_escalate_en_i;
  lc_tx_t lc_rma_req_i;
  lc_tx_t lc_rma_ack_o;
  assign lc_escalate_en_i = LC_TX_DEFAULT;
  assign lc_rma_req_i     = LC_TX_DEFAULT;

  // ----------------------------------------------------------
  // RAM config (tie-off)
  // ----------------------------------------------------------
  ram_1p_cfg_t     ram_cfg_imem_i;
  ram_1p_cfg_t     ram_cfg_dmem_i;
  ram_1p_cfg_rsp_t ram_cfg_rsp_imem_o;
  ram_1p_cfg_rsp_t ram_cfg_rsp_dmem_o;
  assign ram_cfg_imem_i = '0;
  assign ram_cfg_dmem_i = '0;

  // ----------------------------------------------------------
  // EDN (always-ready, fixed entropy)
  // ----------------------------------------------------------
  edn_req_t edn_rnd_o;
  edn_rsp_t edn_rnd_i;
  edn_req_t edn_urnd_o;
  edn_rsp_t edn_urnd_i;

  assign edn_rnd_i.edn_ack  = edn_rnd_o.edn_req;
  assign edn_rnd_i.edn_fips = 1'b1;
  assign edn_rnd_i.edn_bus  = 32'hDEAD_BEEF;
  assign edn_urnd_i.edn_ack  = edn_urnd_o.edn_req;
  assign edn_urnd_i.edn_fips = 1'b1;
  assign edn_urnd_i.edn_bus  = 32'hCAFE_BABE;

  // ----------------------------------------------------------
  // OTP key (respond with fixed key on req)
  // ----------------------------------------------------------
  otbn_otp_key_req_t otbn_otp_key_o;
  otbn_otp_key_rsp_t otbn_otp_key_i;

  always_ff @(posedge clk_otp_i or negedge rst_otp_ni) begin
    if (!rst_otp_ni) begin
      otbn_otp_key_i <= '0;
    end else if (otbn_otp_key_o.req) begin
      otbn_otp_key_i.ack        <= 1'b1;
      otbn_otp_key_i.key        <= 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
      otbn_otp_key_i.nonce      <= 64'hFEED_FACE_CAFE_BEEF;
      otbn_otp_key_i.seed_valid <= 1'b1;
    end else begin
      otbn_otp_key_i.ack <= 1'b0;
    end
  end

  // ----------------------------------------------------------
  // Keymgr sideload key (inactive)
  // ----------------------------------------------------------
  otbn_key_req_t keymgr_key_i;
  assign keymgr_key_i.valid = 1'b0;
  assign keymgr_key_i.key   = '0;

  // ----------------------------------------------------------
  // Other outputs
  // ----------------------------------------------------------
  mubi4_t idle_o;
  logic   intr_done_o;

  // ----------------------------------------------------------
  // DUT
  // ----------------------------------------------------------
  otbn #(
    .RegFile(otbn_pkg::RegFileFF)
  ) u_dut (
    .clk_i,
    .rst_ni,

    .tl_i           (tl_h2d_intg),
    .tl_o           (tl_d2h_dut),

    .idle_o,
    .intr_done_o,

    .alert_rx_i,
    .alert_tx_o,

    .lc_escalate_en_i,
    .lc_rma_req_i,
    .lc_rma_ack_o,

    .ram_cfg_imem_i,
    .ram_cfg_dmem_i,
    .ram_cfg_rsp_imem_o,
    .ram_cfg_rsp_dmem_o,

    .clk_edn_i,
    .rst_edn_ni,
    .edn_rnd_o,
    .edn_rnd_i,
    .edn_urnd_o,
    .edn_urnd_i,

    .clk_otp_i,
    .rst_otp_ni,
    .otbn_otp_key_o,
    .otbn_otp_key_i,

    .keymgr_key_i
  );

  // ----------------------------------------------------------
  // Reset sequence (separate initial block, before run_test)
  // ----------------------------------------------------------
  initial begin
    rst_ni     = 1'b0;
    rst_edn_ni = 1'b0;
    rst_otp_ni = 1'b0;
    repeat (10) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni     = 1'b1;
    rst_edn_ni = 1'b1;
    rst_otp_ni = 1'b1;
  end

  // ----------------------------------------------------------
  // UVM launch (must run at time 0)
  // ----------------------------------------------------------
  initial begin
    uvm_config_db #(virtual otbn_tl_if)::set(null, "uvm_test_top.*", "vif", tl_if);
    run_test();
  end

  // ----------------------------------------------------------
  // FSDB dump
  // ----------------------------------------------------------
  initial begin
    string fsdb_file;
    if ($value$plusargs("fsdbfile+%s", fsdb_file)) begin
      $fsdbDumpfile(fsdb_file);
      $fsdbDumpvars(0, tb_top);
      $fsdbDumpSVA;
    end
  end

  // ----------------------------------------------------------
  // Timeout watchdog
  // ----------------------------------------------------------
  initial begin
    int timeout_ns;
    if (!$value$plusargs("timeout_ns=%d", timeout_ns))
      timeout_ns = 10_000_000;
    #(timeout_ns * 1ns);
    `uvm_fatal("TB_TOP", "Simulation timeout!")
  end

endmodule
