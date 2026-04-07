// =============================================================================
// apb_agent.sv - APB Agent
//
// 根据 apb_agent_cfg 的 role 和 is_active 决定实例化策略：
//
//   role=APB_MASTER, is_active=UVM_ACTIVE  : master_drv + seqr + monitor
//   role=APB_SLAVE,  is_active=UVM_ACTIVE  : slave_drv + req_fifo + rsp_fifo
//                                            + seqr + monitor
//   任意 role,       is_active=UVM_PASSIVE : 仅 monitor
//
// Slave 模式 TLM FIFO 说明：
//   req_fifo: slave_drv 推送观察到的总线请求 → slave sequence 消费
//   rsp_fifo: slave sequence 推送响应数据   → slave_drv 消费
//   slave sequence 通过持有 apb_agent 句柄（p_agent）访问这两个 FIFO。
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
  // Slave 模式专用：TLM FIFO（driver ↔ sequence 双向通信）
  // 深度为 1：每次只处理一笔事务，保证严格的请求-响应顺序
  // -------------------------------------------------------------------------
  uvm_tlm_fifo #(apb_seq_item) req_fifo;  // driver → sequence（观察到的请求）
  uvm_tlm_fifo #(apb_seq_item) rsp_fifo;  // sequence → driver（响应数据）

  // -------------------------------------------------------------------------
  // 配置 & analysis port
  // -------------------------------------------------------------------------
  apb_agent_cfg cfg;
  uvm_analysis_port #(apb_seq_item) ap;

  // -------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = apb_agent_cfg::type_id::create("cfg");
      `uvm_info("APB_AGT", "未获取到 apb_agent_cfg，使用默认配置（master active）", UVM_MEDIUM)
    end

    if (cfg.has_monitor)
      mon = apb_monitor::type_id::create("mon", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      seqr = apb_sequencer::type_id::create("seqr", this);

      case (cfg.role)
        apb_agent_cfg::APB_MASTER : begin
          master_drv = apb_master_driver::type_id::create("master_drv", this);
        end
        apb_agent_cfg::APB_SLAVE : begin
          slave_drv = apb_slave_driver::type_id::create("slave_drv", this);
          // 深度为 1 的 FIFO：请求和响应均严格单次配对，不允许积压
          req_fifo  = new("req_fifo", this, 1);
          rsp_fifo  = new("rsp_fifo", this, 1);
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
          // master driver 通过标准 seq_item_port 从 sequencer 拉取事务
          master_drv.seq_item_port.connect(seqr.seq_item_export);
        end
        apb_agent_cfg::APB_SLAVE : begin
          // slave driver 通过 TLM FIFO 与 slave sequence 双向通信
          // driver.req_port → req_fifo（driver 写入观察到的总线请求）
          slave_drv.req_port.connect(req_fifo.put_export);
          // driver.rsp_port ← rsp_fifo（driver 读取 sequence 提供的响应）
          slave_drv.rsp_port.connect(rsp_fifo.get_export);
          // 注意：slave driver 不连接 seq_item_port，sequencer 仅用于启动 sequence
        end
      endcase
    end

    if (cfg.has_monitor)
      mon.ap.connect(ap);
  endfunction

endclass : apb_agent
