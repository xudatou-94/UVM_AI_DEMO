// =============================================================================
// sjtag2apb_env.sv - sjtag2apb 验证环境
//
// 组件结构：
//   sjtag_agt     : SJTAG VIP，ACTIVE Master 模式，驱动 JTAG 引脚
//   apb_agt       : APB VIP，PASSIVE 模式，仅监听 APB 总线（不驱动）
//   apb_slave     : TB 级 APB 从设备模型，直接驱动 PRDATA/PREADY/PSLVERR
//   scoreboard    : APB 事务记分板，维护影子存储器
//   coverage      : 功能覆盖率收集器
//
// analysis port 连接：
//   apb_agt.ap  → scoreboard.apb_export
//   apb_agt.ap  → coverage.apb_export
//   sjtag_agt.ap → coverage.sjtag_export
// =============================================================================

class sjtag2apb_env extends uvm_env;
  `uvm_component_utils(sjtag2apb_env)

  // --------------------------------------------------------------------------
  // 子组件句柄
  // --------------------------------------------------------------------------
  sjtag_agent                  sjtag_agt;    // SJTAG master agent（ACTIVE）
  apb_agent                    apb_agt;      // APB monitor agent（PASSIVE）
  sjtag2apb_apb_slave_model    apb_slave;    // APB 从设备仿真模型
  sjtag2apb_scoreboard         scoreboard;   // 记分板
  sjtag2apb_coverage           coverage;     // 覆盖率收集器

  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // --------------------------------------------------------------------------
  // build_phase：创建并配置所有子组件
  // --------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    int unsigned tck_half_ns;
    sjtag_agent_cfg  s_cfg;
    apb_agent_cfg    a_cfg;

    super.build_phase(phase);

    // ---- SJTAG Agent 配置：ACTIVE Master ----
    s_cfg = sjtag_agent_cfg::type_id::create("s_cfg");
    s_cfg.is_active = UVM_ACTIVE;
    // 从 config_db 读取 TCK 频率配置（由 base_test 传入）
    if (!uvm_config_db #(int unsigned)::get(this, "", "tck_half_period_ns", tck_half_ns))
      tck_half_ns = 50;  // 默认 100ns 周期（10MHz）
    s_cfg.tck_half_period_ns = tck_half_ns;
    uvm_config_db #(sjtag_agent_cfg)::set(this, "sjtag_agt", "cfg", s_cfg);

    // ---- APB Agent 配置：PASSIVE（仅 monitor） ----
    a_cfg = apb_agent_cfg::type_id::create("a_cfg");
    a_cfg.is_active  = UVM_PASSIVE;
    a_cfg.has_monitor = 1;
    uvm_config_db #(apb_agent_cfg)::set(this, "apb_agt", "cfg", a_cfg);

    // ---- 创建子组件 ----
    sjtag_agt  = sjtag_agent::type_id::create("sjtag_agt",  this);
    apb_agt    = apb_agent::type_id::create("apb_agt",      this);
    apb_slave  = sjtag2apb_apb_slave_model::type_id::create("apb_slave", this);
    scoreboard = sjtag2apb_scoreboard::type_id::create("scoreboard",      this);
    coverage   = sjtag2apb_coverage::type_id::create("coverage",          this);
  endfunction

  // --------------------------------------------------------------------------
  // connect_phase：连接 analysis port
  // --------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    // APB monitor → scoreboard（写操作更新影子存储器，读操作校验）
    apb_agt.ap.connect(scoreboard.apb_export);

    // APB monitor → coverage（采样 APB 功能覆盖率）
    apb_agt.ap.connect(coverage.apb_export);

    // SJTAG monitor → coverage（采样 SJTAG 操作类型覆盖率）
    sjtag_agt.ap.connect(coverage.sjtag_export);
  endfunction

endclass : sjtag2apb_env
