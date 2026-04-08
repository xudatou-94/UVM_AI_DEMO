// ============================================================
// OTBN TL-UL Monitor
// Captures completed TL-UL transactions and broadcasts via ap
// ============================================================
class otbn_tl_monitor extends uvm_monitor;
  `uvm_component_utils(otbn_tl_monitor)

  virtual otbn_tl_if              vif;
  otbn_tl_agent_cfg               cfg;
  uvm_analysis_port #(otbn_tl_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual otbn_tl_if)::get(this, "", "vif", vif))
      `uvm_fatal(`gfn, "Cannot get otbn_tl_if from config_db")
    if (!uvm_config_db #(otbn_tl_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal(`gfn, "Cannot get otbn_tl_agent_cfg from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    import tlul_pkg::*;

    otbn_tl_seq_item pend_item;
    bit              pend_valid = 0;

    @(posedge vif.rst_n);

    forever begin
      @(vif.monitor_cb);

      // Capture request phase
      if (vif.monitor_cb.h2d.a_valid && vif.monitor_cb.d2h.a_ready && !pend_valid) begin
        pend_item       = otbn_tl_seq_item::type_id::create("tl_item");
        pend_item.write = (vif.monitor_cb.h2d.a_opcode == PutFullData ||
                           vif.monitor_cb.h2d.a_opcode == PutPartialData);
        pend_item.addr  = vif.monitor_cb.h2d.a_address;
        pend_item.wdata = vif.monitor_cb.h2d.a_data;
        pend_item.mask  = vif.monitor_cb.h2d.a_mask;
        pend_valid      = 1;
      end

      // Capture response phase
      if (vif.monitor_cb.d2h.d_valid && vif.monitor_cb.h2d.d_ready && pend_valid) begin
        pend_item.rdata = vif.monitor_cb.d2h.d_data;
        pend_item.error = vif.monitor_cb.d2h.d_error;
        ap.write(pend_item);
        pend_valid = 0;
      end
    end
  endtask

endclass
