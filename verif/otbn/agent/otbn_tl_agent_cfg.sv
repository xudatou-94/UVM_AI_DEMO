// ============================================================
// OTBN TL-UL Agent Config
// ============================================================
class otbn_tl_agent_cfg extends uvm_object;
  `uvm_object_utils(otbn_tl_agent_cfg)

  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Max cycles to wait for a_ready
  int unsigned req_timeout_cycles = 1000;
  // Max cycles to wait for d_valid
  int unsigned rsp_timeout_cycles = 1000;

  function new(string name = "otbn_tl_agent_cfg");
    super.new(name);
  endfunction

endclass
