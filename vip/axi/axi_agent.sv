// =============================================================================
// axi_agent.sv  AXI4 Agent
//
// 支持三种模式：
//   - Master Active  : sequencer + master_driver + monitor
//   - Slave  Active  : sequencer + slave_driver  + monitor
//   - Passive        : monitor only
//
// Analysis Ports（对外暴露 monitor 的输出）：
//   ap_write, ap_read
// =============================================================================
class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  import axi_pkg::*;

  // ---- 子组件 ----
  axi_sequencer    sequencer;
  axi_master_driver master_drv;
  axi_slave_driver  slave_drv;
  axi_monitor       monitor;

  // ---- 配置 ----
  axi_agent_cfg cfg;

  // ---- Analysis Ports（透传 monitor 输出）----
  uvm_analysis_port #(axi_seq_item) ap_write;
  uvm_analysis_port #(axi_seq_item) ap_read;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 获取配置
    if (!uvm_config_db #(axi_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = new("cfg");
      `uvm_info("CFG", "axi_agent: using default cfg (master active)", UVM_LOW)
    end

    // 透传配置给子组件
    uvm_config_db #(axi_agent_cfg)::set(this, "*", "cfg", cfg);

    // 按模式创建组件
    if (cfg.is_active) begin
      sequencer = axi_sequencer::type_id::create("sequencer", this);
      if (cfg.role == AXI_MASTER)
        master_drv = axi_master_driver::type_id::create("master_drv", this);
      else
        slave_drv = axi_slave_driver::type_id::create("slave_drv", this);
    end

    // monitor 始终创建
    monitor = axi_monitor::type_id::create("monitor", this);

    // Analysis Ports
    ap_write = new("ap_write", this);
    ap_read  = new("ap_read",  this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // 连接 driver <-> sequencer
    if (cfg.is_active) begin
      if (cfg.role == AXI_MASTER)
        master_drv.seq_item_port.connect(sequencer.seq_item_export);
      else
        slave_drv.seq_item_port.connect(sequencer.seq_item_export);
    end

    // 透传 monitor analysis port
    monitor.ap_write.connect(ap_write);
    monitor.ap_read.connect(ap_read);
  endfunction

endclass
