// ============================================================
// OTBN Environment Config
// ============================================================
class otbn_env_cfg extends uvm_object;
  `uvm_object_utils(otbn_env_cfg)

  otbn_tl_agent_cfg tl_agent_cfg;

  // Max cycles to poll STATUS before timeout
  int unsigned run_timeout_cycles = 100_000;

  function new(string name = "otbn_env_cfg");
    super.new(name);
    tl_agent_cfg = otbn_tl_agent_cfg::type_id::create("tl_agent_cfg");
  endfunction

endclass
