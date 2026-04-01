// =============================================================================
// axi_agent_cfg.sv  AXI Agent 配置对象
//
// 包含：
//   - agent 角色（master / slave）
//   - 是否激活（active/passive）
//   - outstanding 上限
//   - AWREADY / ARREADY 全局默认反压（V1：per-transaction 暂不支持）
// =============================================================================
class axi_agent_cfg extends uvm_object;
  `uvm_object_utils_begin(axi_agent_cfg)
    `uvm_field_enum  (axi_pkg::axi_role_e, role,          UVM_ALL_ON)
    `uvm_field_int   (is_active,                           UVM_ALL_ON)
    `uvm_field_int   (max_outstanding,                     UVM_ALL_ON)
    `uvm_field_enum  (axi_pkg::axi_bp_mode_e, awready_bp_mode, UVM_ALL_ON)
    `uvm_field_int   (awready_bp_fixed,                    UVM_ALL_ON)
    `uvm_field_int   (awready_bp_min,                      UVM_ALL_ON)
    `uvm_field_int   (awready_bp_max,                      UVM_ALL_ON)
    `uvm_field_enum  (axi_pkg::axi_bp_mode_e, arready_bp_mode, UVM_ALL_ON)
    `uvm_field_int   (arready_bp_fixed,                    UVM_ALL_ON)
    `uvm_field_int   (arready_bp_min,                      UVM_ALL_ON)
    `uvm_field_int   (arready_bp_max,                      UVM_ALL_ON)
  `uvm_object_utils_end

  import axi_pkg::*;

  // ---- 角色与激活模式 ----
  axi_role_e  role       = AXI_MASTER;
  bit         is_active  = 1;           // 1=active, 0=passive（仅 monitor）

  // ---- outstanding 上限（仅 master 有效）----
  // master driver 同时允许飞行中的最大事务数
  int unsigned max_outstanding = 8;

  // ---- AWREADY 全局反压（slave driver 使用，V1 限制）----
  axi_bp_mode_e  awready_bp_mode  = AXI_BP_NONE;
  int unsigned   awready_bp_fixed = 0;
  int unsigned   awready_bp_min   = 0;
  int unsigned   awready_bp_max   = 4;

  // ---- ARREADY 全局反压（slave driver 使用，V1 限制）----
  axi_bp_mode_e  arready_bp_mode  = AXI_BP_NONE;
  int unsigned   arready_bp_fixed = 0;
  int unsigned   arready_bp_min   = 0;
  int unsigned   arready_bp_max   = 4;

  function new(string name = "axi_agent_cfg");
    super.new(name);
  endfunction

  // 便捷构建函数
  static function axi_agent_cfg create_master_cfg(
    string name          = "master_cfg",
    int unsigned max_os  = 8
  );
    axi_agent_cfg cfg = new(name);
    cfg.role            = AXI_MASTER;
    cfg.is_active       = 1;
    cfg.max_outstanding = max_os;
    return cfg;
  endfunction

  static function axi_agent_cfg create_slave_cfg(
    string name = "slave_cfg"
  );
    axi_agent_cfg cfg = new(name);
    cfg.role      = AXI_SLAVE;
    cfg.is_active = 1;
    return cfg;
  endfunction

  static function axi_agent_cfg create_monitor_cfg(
    string name = "monitor_cfg"
  );
    axi_agent_cfg cfg = new(name);
    cfg.is_active = 0;
    return cfg;
  endfunction

endclass
