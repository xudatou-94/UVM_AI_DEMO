// ============================================================
// OTBN Base Test
// ============================================================
class otbn_base_test extends uvm_test;
  `uvm_component_utils(otbn_base_test)

  otbn_env     env;
  otbn_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = otbn_env_cfg::type_id::create("cfg");
    uvm_config_db #(otbn_env_cfg)::set(this, "env", "cfg", cfg);

    env = otbn_env::type_id::create("env", this);
  endfunction

  // Helper: get TL sequencer from env
  function uvm_sequencer #(otbn_tl_seq_item) get_tl_seqr();
    return env.tl_agent.sequencer;
  endfunction

  function otbn_scoreboard get_scoreboard();
    return env.scoreboard;
  endfunction

endclass
