// ============================================================
// OTBN Environment
// ============================================================
class otbn_env extends uvm_env;
  `uvm_component_utils(otbn_env)

  otbn_env_cfg      cfg;
  otbn_tl_agent     tl_agent;
  otbn_scoreboard   scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(otbn_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = otbn_env_cfg::type_id::create("cfg");
      `uvm_info(`gfn, "otbn_env_cfg not found, using default", UVM_LOW)
    end

    // Propagate tl_agent_cfg
    uvm_config_db #(otbn_tl_agent_cfg)::set(this, "tl_agent", "cfg", cfg.tl_agent_cfg);

    tl_agent   = otbn_tl_agent::type_id::create("tl_agent", this);
    scoreboard = otbn_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    tl_agent.ap.connect(scoreboard.tl_ap);
  endfunction

endclass
