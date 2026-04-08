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
  localparam int CLK_PERIOD_NS  = 10;  // 100 MHz
  localparam int CLK_EDN_NS     = 10;
  localparam int CLK_OTP_NS     = 10;
  localparam int NumAlerts      = otbn_reg_pkg::NumAlerts;

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
  always #(CLK_EDN_NS/2) clk_edn_i = ~clk_edn_i;

  initial clk_otp_i = 1'b0;
  always #(CLK_OTP_NS/2) clk_otp_i = ~clk_otp_i;

  // ----------------------------------------------------------
  // TL-UL interface signals
  // ----------------------------------------------------------
  tl_h2d_t tl_i;
  tl_d2h_t tl_o;

  // ----------------------------------------------------------
  // Alert interface
  // ----------------------------------------------------------
  alert_rx_t [NumAlerts-1:0] alert_rx_i;
  alert_tx_t [NumAlerts-1:0] alert_tx_o;

  // ----------------------------------------------------------
  // EDN interface
  // ----------------------------------------------------------
  edn_req_t edn_rnd_o;
  edn_rsp_t edn_rnd_i;
  edn_req_t edn_urnd_o;
  edn_rsp_t edn_urnd_i;

  // ----------------------------------------------------------
  // OTP key interface
  // ----------------------------------------------------------
  otbn_otp_key_req_t otbn_otp_key_o;
  otbn_otp_key_rsp_t otbn_otp_key_i;

  // ----------------------------------------------------------
  // Keymgr sideload key
  // ----------------------------------------------------------
  otbn_key_req_t keymgr_key_i;

  // ----------------------------------------------------------
  // RAM config (tie-off)
  // ----------------------------------------------------------
  ram_1p_cfg_t     ram_cfg_imem_i;
  ram_1p_cfg_t     ram_cfg_dmem_i;
  ram_1p_cfg_rsp_t ram_cfg_rsp_imem_o;
  ram_1p_cfg_rsp_t ram_cfg_rsp_dmem_o;

  // ----------------------------------------------------------
  // Other outputs
  // ----------------------------------------------------------
  mubi4_t idle_o;
  logic   intr_done_o;
  lc_tx_t lc_rma_ack_o;

  // ----------------------------------------------------------
  // Tie-offs for unused inputs
  // ----------------------------------------------------------
  // Alert: drive p/n to inactive
  always_comb begin
    for (int i = 0; i < NumAlerts; i++) begin
      alert_rx_i[i].ack_p  = 1'b0;
      alert_rx_i[i].ack_n  = 1'b1;
      alert_rx_i[i].ping_p = 1'b0;
      alert_rx_i[i].ping_n = 1'b1;
    end
  end

  // LC: off by default
  lc_tx_t lc_escalate_en_i;
  lc_tx_t lc_rma_req_i;
  assign lc_escalate_en_i = LC_TX_DEFAULT;
  assign lc_rma_req_i     = LC_TX_DEFAULT;

  // RAM config: all zeros (tie-off)
  assign ram_cfg_imem_i = '0;
  assign ram_cfg_dmem_i = '0;

  // EDN: always ready, return fixed entropy
  assign edn_rnd_i.edn_ack  = edn_rnd_o.edn_req;
  assign edn_rnd_i.edn_fips = 1'b1;
  assign edn_rnd_i.edn_bus  = 32'hDEAD_BEEF;

  assign edn_urnd_i.edn_ack  = edn_urnd_o.edn_req;
  assign edn_urnd_i.edn_fips = 1'b1;
  assign edn_urnd_i.edn_bus  = 32'hCAFE_BABE;

  // OTP key: provide valid default key
  always_ff @(posedge clk_otp_i or negedge rst_otp_ni) begin
    if (!rst_otp_ni) begin
      otbn_otp_key_i <= '0;
    end else if (otbn_otp_key_o.req) begin
      otbn_otp_key_i.ack   <= 1'b1;
      otbn_otp_key_i.key   <= 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
      otbn_otp_key_i.nonce <= 64'hFEED_FACE_CAFE_BEEF;
      otbn_otp_key_i.seed_valid <= 1'b1;
    end else begin
      otbn_otp_key_i.ack <= 1'b0;
    end
  end

  // Keymgr sideload key: not valid by default
  assign keymgr_key_i.valid  = 1'b0;
  assign keymgr_key_i.key    = '0;

  // ----------------------------------------------------------
  // DUT
  // ----------------------------------------------------------
  otbn #(
    .RegFile(otbn_pkg::RegFileFF)
  ) u_dut (
    .clk_i,
    .rst_ni,

    .tl_i,
    .tl_o,

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
  // Reset sequence
  // ----------------------------------------------------------
  initial begin
    rst_ni     = 1'b0;
    rst_edn_ni = 1'b0;
    rst_otp_ni = 1'b0;
    tl_i       = '0;
    repeat (10) @(posedge clk_i);
    rst_ni     = 1'b1;
    rst_edn_ni = 1'b1;
    rst_otp_ni = 1'b1;
  end

  // ----------------------------------------------------------
  // UVM launch
  // ----------------------------------------------------------
  initial begin
    // Pass interface handles to UVM config DB
    uvm_config_db #(virtual interface_placeholder)::set(null, "*", "vif", null);
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
