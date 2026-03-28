// =============================================================================
// apb_agent_cfg.sv - APB Agent 配置对象
//
// 通过 uvm_config_db 传递给 apb_agent，控制 agent 行为。
// =============================================================================

class apb_agent_cfg extends uvm_object;
  `uvm_object_utils(apb_agent_cfg)

  // -------------------------------------------------------------------------
  // 角色配置
  // -------------------------------------------------------------------------

  // is_active：UVM_ACTIVE 时创建 driver+sequencer；UVM_PASSIVE 时仅创建 monitor
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // 角色：master 主动发起事务；slave 被动响应事务
  typedef enum { APB_MASTER, APB_SLAVE } apb_role_e;
  apb_role_e role = APB_MASTER;

  // -------------------------------------------------------------------------
  // Slave 行为配置
  // -------------------------------------------------------------------------

  // slave 默认响应延迟（wait_states 的默认值，可被 seq_item 覆盖）
  int unsigned default_wait_states = 0;

  // slave 默认 PSLVERR 响应（0=正常，1=错误）
  bit default_pslverr = 0;

  // -------------------------------------------------------------------------
  // Monitor 配置
  // -------------------------------------------------------------------------
  bit has_monitor = 1;

  // -------------------------------------------------------------------------
  // 总线参数（与 apb_if 参数须一致）
  // -------------------------------------------------------------------------
  int unsigned addr_width = 32;
  int unsigned data_width = 32;

  // -------------------------------------------------------------------------
  function new(string name = "apb_agent_cfg");
    super.new(name);
  endfunction

endclass : apb_agent_cfg
