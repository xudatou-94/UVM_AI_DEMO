// =============================================================================
// sjtag_agent.sv - SJTAG Agent
//
// 根据 sjtag_agent_cfg.is_active 决定是否实例化 driver+sequencer：
//   UVM_ACTIVE  : driver + sequencer + monitor（可选）
//   UVM_PASSIVE : 仅 monitor
//
// 对外暴露 analysis_port 转发 monitor 的输出。
// =============================================================================

class sjtag_agent extends uvm_agent;
  `uvm_component_utils(sjtag_agent)

  // -------------------------------------------------------------------------
  // 子组件
  // -------------------------------------------------------------------------
  sjtag_driver     drv;
  sjtag_sequencer  seqr;
  sjtag_monitor    mon;

  // -------------------------------------------------------------------------
  // 配置
  // -------------------------------------------------------------------------
  sjtag_agent_cfg cfg;

  // -------------------------------------------------------------------------
  // analysis port（转发 monitor 输出，方便 env 直接连接）
  // -------------------------------------------------------------------------
  uvm_analysis_port #(sjtag_seq_item) ap;

  // -------------------------------------------------------------------------
  // 构造函数
  // -------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase：按配置创建子组件
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 获取配置，若未配置则使用默认值
    if (!uvm_config_db #(sjtag_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sjtag_agent_cfg::type_id::create("cfg");
      `uvm_info("SJTAG_AGT", "未获取到 sjtag_agent_cfg，使用默认配置", UVM_MEDIUM)
    end

    // monitor（active/passive 均可创建）
    if (cfg.has_monitor) begin
      mon = sjtag_monitor::type_id::create("mon", this);
    end

    // driver + sequencer（仅 ACTIVE 模式）
    if (cfg.is_active == UVM_ACTIVE) begin
      drv  = sjtag_driver::type_id::create("drv", this);
      seqr = sjtag_sequencer::type_id::create("seqr", this);
      // 将 tck_half_period_ns 传递给 driver
      uvm_config_db #(int unsigned)::set(this, "drv", "tck_half_period_ns",
                                         cfg.tck_half_period_ns);
    end

    ap = new("ap", this);
  endfunction

  // -------------------------------------------------------------------------
  // connect_phase：连接内部端口
  // -------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end
    if (cfg.has_monitor) begin
      mon.ap.connect(ap);
    end
  endfunction

endclass : sjtag_agent
