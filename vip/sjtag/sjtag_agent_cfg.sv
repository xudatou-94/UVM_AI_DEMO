// =============================================================================
// sjtag_agent_cfg.sv - SJTAG Agent 配置对象
//
// 通过 uvm_config_db 传递给 sjtag_agent，控制 agent 行为。
// =============================================================================

class sjtag_agent_cfg extends uvm_object;
  `uvm_object_utils(sjtag_agent_cfg)

  // -------------------------------------------------------------------------
  // 配置字段
  // -------------------------------------------------------------------------

  // active：UVM_ACTIVE 时创建 driver+sequencer；UVM_PASSIVE 时仅创建 monitor
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // TCK 半周期（ns），传递给 driver
  int unsigned tck_half_period_ns = 50;  // 默认 100ns（10MHz）

  // 是否启用 monitor（active 和 passive 模式均可关闭）
  bit has_monitor = 1;

  // -------------------------------------------------------------------------
  function new(string name = "sjtag_agent_cfg");
    super.new(name);
  endfunction

endclass : sjtag_agent_cfg
