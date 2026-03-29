// =============================================================================
// sjtag2apb_env.sv - sjtag2apb 验证环境
//
// 组件结构：
//   sjtag_agt    : SJTAG VIP，ACTIVE Master 模式，驱动 JTAG 引脚
//   apb_agt      : APB VIP，ACTIVE Slave 模式，通过 TLM FIFO 响应 APB 总线
//   apb_slv_seq  : APB Slave 响应 sequence，内置内存模型，后台持续运行
//   scoreboard   : APB 事务记分板，维护影子存储器
//   coverage     : 功能覆盖率收集器
//
// analysis port 连接：
//   apb_agt.ap   → scoreboard.apb_export
//   apb_agt.ap   → coverage.apb_export
//   sjtag_agt.ap → coverage.sjtag_export
//
// Slave 响应机制（TLM FIFO）：
//   apb_agt（ACTIVE SLAVE） 内部有 req_fifo / rsp_fifo；
//   apb_slv_seq 持有 apb_agt 句柄，在 run_phase 后台循环
//   从 req_fifo 获取 driver 观察到的请求，返回响应到 rsp_fifo。
//   测试激励通过 p_env.apb_slv_seq 动态修改内存/wait_states/pslverr。
// =============================================================================

class sjtag2apb_env extends uvm_env;
  `uvm_component_utils(sjtag2apb_env)

  // --------------------------------------------------------------------------
  // 子组件句柄
  // --------------------------------------------------------------------------
  sjtag_agent          sjtag_agt;    // SJTAG master agent（ACTIVE）
  apb_agent            apb_agt;      // APB slave agent（ACTIVE SLAVE）
  sjtag2apb_scoreboard scoreboard;   // 记分板
  sjtag2apb_coverage   coverage;     // 覆盖率收集器

  // --------------------------------------------------------------------------
  // APB slave 响应 sequence（后台运行，内置内存模型）
  // 测试激励可通过此句柄配置：
  //   apb_slv_seq.mem[addr]           = data    // 预置/修改读数据
  //   apb_slv_seq.default_wait_states = n       // 全局等待状态
  //   apb_slv_seq.pslverr_addrs[addr] = 1/0    // PSLVERR 注入
  // --------------------------------------------------------------------------
  apb_slave_resp_seq apb_slv_seq;

  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // --------------------------------------------------------------------------
  // build_phase
  // --------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    int unsigned tck_half_ns;
    sjtag_agent_cfg s_cfg;
    apb_agent_cfg   a_cfg;

    super.build_phase(phase);

    // ---- SJTAG Agent：ACTIVE Master ----
    s_cfg = sjtag_agent_cfg::type_id::create("s_cfg");
    s_cfg.is_active = UVM_ACTIVE;
    if (!uvm_config_db #(int unsigned)::get(this, "", "tck_half_period_ns", tck_half_ns))
      tck_half_ns = 50;
    s_cfg.tck_half_period_ns = tck_half_ns;
    uvm_config_db #(sjtag_agent_cfg)::set(this, "sjtag_agt", "cfg", s_cfg);

    // ---- APB Agent：ACTIVE Slave + Monitor ----
    a_cfg = apb_agent_cfg::type_id::create("a_cfg");
    a_cfg.role        = apb_agent_cfg::APB_SLAVE;
    a_cfg.is_active   = UVM_ACTIVE;
    a_cfg.has_monitor = 1;
    uvm_config_db #(apb_agent_cfg)::set(this, "apb_agt", "cfg", a_cfg);

    // ---- 创建组件 ----
    sjtag_agt  = sjtag_agent::type_id::create("sjtag_agt",  this);
    apb_agt    = apb_agent::type_id::create("apb_agt",      this);
    scoreboard = sjtag2apb_scoreboard::type_id::create("scoreboard", this);
    coverage   = sjtag2apb_coverage::type_id::create("coverage",     this);

    // ---- 创建 slave response sequence（build 时创建，run 时启动）----
    apb_slv_seq = apb_slave_resp_seq::type_id::create("apb_slv_seq");
  endfunction

  // --------------------------------------------------------------------------
  // connect_phase
  // --------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    apb_agt.ap.connect(scoreboard.apb_export);
    apb_agt.ap.connect(coverage.apb_export);
    sjtag_agt.ap.connect(coverage.sjtag_export);
  endfunction

  // --------------------------------------------------------------------------
  // run_phase：后台启动 APB slave 响应 sequence
  // --------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    // 设置 agent 句柄后在独立线程中启动（不阻塞主流程）
    apb_slv_seq.p_agent = apb_agt;
    fork
      apb_slv_seq.start(null);
    join_none
  endtask

endclass : sjtag2apb_env
