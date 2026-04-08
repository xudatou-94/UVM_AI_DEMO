// ============================================================
// OTBN TL-UL Agent
// ============================================================
class otbn_tl_agent extends uvm_agent;
  `uvm_component_utils(otbn_tl_agent)

  otbn_tl_agent_cfg                   cfg;
  otbn_tl_driver                      driver;
  otbn_tl_monitor                     monitor;
  uvm_sequencer #(otbn_tl_seq_item)   sequencer;

  uvm_analysis_port #(otbn_tl_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(otbn_tl_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = otbn_tl_agent_cfg::type_id::create("cfg");
    end

    monitor = otbn_tl_monitor::type_id::create("monitor", this);
    uvm_config_db #(otbn_tl_agent_cfg)::set(this, "monitor", "cfg", cfg);

    if (cfg.is_active == UVM_ACTIVE) begin
      driver    = otbn_tl_driver::type_id::create("driver", this);
      sequencer = uvm_sequencer #(otbn_tl_seq_item)::type_id::create("sequencer", this);
      uvm_config_db #(otbn_tl_agent_cfg)::set(this, "driver", "cfg", cfg);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    ap = monitor.ap;
    if (cfg.is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass
