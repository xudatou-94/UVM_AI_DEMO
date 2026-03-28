// =============================================================================
// apb_agent.sv - APB Agent
//
// 根据 apb_agent_cfg 的 role 和 is_active 决定实例化策略：
//
//   role=APB_MASTER, is_active=UVM_ACTIVE  : master_drv + seqr + monitor
//   role=APB_SLAVE,  is_active=UVM_ACTIVE  : slave_drv  + seqr + monitor
//   任意 role,       is_active=UVM_PASSIVE : 仅 monitor
//
// 对外暴露 analysis_port（转发 monitor 输出）。
// =============================================================================

class apb_agent extends uvm_agent;
  `uvm_component_utils(apb_agent)

  // -------------------------------------------------------------------------
  // 子组件
  // -------------------------------------------------------------------------
  apb_master_driver  master_drv;
  apb_slave_driver   slave_drv;
  apb_sequencer      seqr;
  apb_monitor        mon;

  // -------------------------------------------------------------------------
  // 配置
  // -------------------------------------------------------------------------
  apb_agent_cfg cfg;

  // -------------------------------------------------------------------------
  // analysis port
  // -------------------------------------------------------------------------
  uvm_analysis_port #(apb_seq_item) ap;

  // -------------------------------------------------------------------------
  // 构造函数
  // -------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 获取配置，若未配置则使用默认值
    if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = apb_agent_cfg::type_id::create("cfg");
      `uvm_info("APB_AGT", "未获取到 apb_agent_cfg，使用默认配置（master active）", UVM_MEDIUM)
    end

    // 将 cfg 传递给 driver（slave driver 需要读取 cfg 中的默认值）
    uvm_config_db #(apb_agent_cfg)::set(this, "slave_drv", "cfg", cfg);

    // monitor
    if (cfg.has_monitor) begin
      mon = apb_monitor::type_id::create("mon", this);
    end

    // driver + sequencer（仅 ACTIVE 模式）
    if (cfg.is_active == UVM_ACTIVE) begin
      seqr = apb_sequencer::type_id::create("seqr", this);
      case (cfg.role)
        apb_agent_cfg::APB_MASTER : begin
          master_drv = apb_master_driver::type_id::create("master_drv", this);
        end
        apb_agent_cfg::APB_SLAVE : begin
          slave_drv = apb_slave_driver::type_id::create("slave_drv", this);
        end
      endcase
    end

    ap = new("ap", this);
  endfunction

  // -------------------------------------------------------------------------
  // connect_phase
  // -------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      case (cfg.role)
        apb_agent_cfg::APB_MASTER : begin
          master_drv.seq_item_port.connect(seqr.seq_item_export);
        end
        apb_agent_cfg::APB_SLAVE : begin
          slave_drv.seq_item_port.connect(seqr.seq_item_export);
        end
      endcase
    end
    if (cfg.has_monitor) begin
      mon.ap.connect(ap);
    end
  endfunction

endclass : apb_agent
