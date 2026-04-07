// =============================================================================
// apb_monitor.sv - APB Monitor
//
// 功能：
//   被动监听 APB 总线，在 ACCESS 阶段（PSEL & PENABLE & PREADY）完成时
//   采样完整的事务信息，通过 analysis_port 广播 apb_seq_item。
//
// 采样时刻：
//   @(posedge PCLK)，在 PSEL & PENABLE & PREADY 同时为高时采样。
//   这是 APB 事务最终完成的时钟沿。
// =============================================================================

class apb_monitor extends uvm_monitor;
  `uvm_component_utils(apb_monitor)

  // -------------------------------------------------------------------------
  // 端口 & 接口
  // -------------------------------------------------------------------------
  uvm_analysis_port #(apb_seq_item) ap;
  virtual apb_if vif;

  // -------------------------------------------------------------------------
  // 构造函数 & build_phase
  // -------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "apb_monitor: 未获取到 virtual apb_if")
  endfunction

  // -------------------------------------------------------------------------
  // run_phase：等待复位后持续采样
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    @(posedge vif.PRESETn);

    forever begin
      @(posedge vif.PCLK);
      if (!vif.PRESETn) continue;

      // APB 事务完成条件：PSEL & PENABLE & PREADY
      if (vif.PSEL && vif.PENABLE && vif.PREADY) begin
        apb_seq_item item;
        item = apb_seq_item::type_id::create("mon_item");
        item.addr    = vif.PADDR;
        item.rw      = vif.PWRITE;
        item.wdata   = vif.PWDATA;
        item.rdata   = vif.PRDATA;
        item.pslverr = vif.PSLVERR;
        item.pprot   = vif.PPROT;
        item.pstrb   = vif.PSTRB;

        `uvm_info("APB_MON", $sformatf("监测到事务: %s", item.convert2string()), UVM_MEDIUM)
        ap.write(item);
      end
    end
  endtask

endclass : apb_monitor
