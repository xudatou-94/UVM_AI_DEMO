// ============================================================
// OTBN TL-UL Driver
// Drives single-beat TL-UL transactions (blocking).
// Integrity is computed externally by tlul_cmd_intg_gen in TB top.
// ============================================================
class otbn_tl_driver extends uvm_driver #(otbn_tl_seq_item);
  `uvm_component_utils(otbn_tl_driver)

  virtual otbn_tl_if vif;
  otbn_tl_agent_cfg  cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual otbn_tl_if)::get(this, "", "vif", vif))
      `uvm_fatal(`gfn, "Cannot get otbn_tl_if from config_db")
    if (!uvm_config_db #(otbn_tl_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal(`gfn, "Cannot get otbn_tl_agent_cfg from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    import tlul_pkg::*;

    // Idle default
    vif.h2d <= tlul_pkg::TL_H2D_DEFAULT;
    @(posedge vif.rst_n);
    @(posedge vif.clk);

    forever begin
      otbn_tl_seq_item req;
      seq_item_port.get_next_item(req);
      drive_txn(req);
      seq_item_port.item_done();
    end
  endtask

  // Drive one blocking TL-UL transaction
  task drive_txn(otbn_tl_seq_item req);
    import tlul_pkg::*;

    int unsigned wait_cnt;
    tl_h2d_t h2d;

    // Build request (integrity fields left as default — filled by tlul_cmd_intg_gen)
    h2d          = TL_H2D_DEFAULT;
    h2d.a_valid  = 1'b1;
    h2d.a_opcode = req.write ? PutFullData : Get;
    h2d.a_param  = '0;
    h2d.a_size   = 2'b10;         // 4 bytes
    h2d.a_source = '0;
    h2d.a_address = req.addr;
    h2d.a_mask   = req.mask;
    h2d.a_data   = req.wdata;
    h2d.d_ready  = 1'b1;

    // Phase 1: send request, wait for a_ready
    @(vif.driver_cb);
    vif.driver_cb.h2d <= h2d;

    wait_cnt = 0;
    while (!vif.driver_cb.d2h.a_ready) begin
      @(vif.driver_cb);
      wait_cnt++;
      if (wait_cnt >= cfg.req_timeout_cycles)
        `uvm_fatal(`gfn, $sformatf("a_ready timeout addr=0x%08x", req.addr))
    end

    // De-assert a_valid after handshake
    h2d.a_valid = 1'b0;
    @(vif.driver_cb);
    vif.driver_cb.h2d <= h2d;

    // Phase 2: wait for d_valid (d_ready already set in h2d)
    wait_cnt = 0;
    while (!vif.driver_cb.d2h.d_valid) begin
      @(vif.driver_cb);
      wait_cnt++;
      if (wait_cnt >= cfg.rsp_timeout_cycles)
        `uvm_fatal(`gfn, $sformatf("d_valid timeout addr=0x%08x", req.addr))
    end

    req.rdata = vif.driver_cb.d2h.d_data;
    req.error = vif.driver_cb.d2h.d_error;

    // Drop d_ready
    h2d.d_ready = 1'b0;
    @(vif.driver_cb);
    vif.driver_cb.h2d <= h2d;

    `uvm_info(`gfn, $sformatf("TL txn: %s", req.convert2string()), UVM_HIGH)
  endtask

endclass
