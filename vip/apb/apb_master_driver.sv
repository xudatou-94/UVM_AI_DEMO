// =============================================================================
// apb_master_driver.sv - APB Master Driver
//
// 将 apb_seq_item 翻译为 APB 总线时序，遵循 APB3/APB4 协议：
//   - SETUP 阶段：拉高 PSEL，给出 PADDR/PWRITE/PWDATA/PPROT/PSTRB
//   - ACCESS 阶段：拉高 PENABLE，等待 PREADY
//   - 事务完成后：拉低 PSEL/PENABLE，回到 IDLE
// =============================================================================

class apb_master_driver extends uvm_driver #(apb_seq_item);
  `uvm_component_utils(apb_master_driver)

  virtual apb_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "apb_master_driver: 未获取到 virtual apb_if")
  endfunction

  // -------------------------------------------------------------------------
  // run_phase：初始化后循环驱动事务
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    // 初始化总线为 IDLE 状态
    bus_idle();
    // 等待复位释放
    @(posedge vif.PRESETn);
    @(posedge vif.PCLK);

    forever begin
      apb_seq_item req, rsp;
      seq_item_port.get_next_item(req);
      `uvm_info("APB_MDRV", $sformatf("执行: %s", req.convert2string()), UVM_MEDIUM)

      rsp = apb_seq_item::type_id::create("rsp");
      rsp.copy(req);

      drive_transfer(rsp);
      seq_item_port.item_done(rsp);
    end
  endtask

  // -------------------------------------------------------------------------
  // 驱动单次 APB 事务
  // -------------------------------------------------------------------------
  task drive_transfer(apb_seq_item item);
    // ---------- SETUP 阶段 ----------
    @(posedge vif.PCLK);
    #1;  // 时钟后延迟赋值（避免 setup time 问题）
    vif.PADDR   = item.addr;
    vif.PWRITE  = item.rw;
    vif.PWDATA  = item.rw ? item.wdata : '0;
    vif.PPROT   = item.pprot;
    vif.PSTRB   = item.rw ? item.pstrb : '0;
    vif.PSEL    = 1;
    vif.PENABLE = 0;

    // ---------- ACCESS 阶段 ----------
    @(posedge vif.PCLK);
    #1;
    vif.PENABLE = 1;

    // 等待 PREADY（从设备就绪）
    do begin
      @(posedge vif.PCLK);
    end while (!vif.PREADY);

    // 采样响应
    if (!item.rw) begin
      item.rdata = vif.PRDATA;
    end
    item.pslverr = vif.PSLVERR;

    `uvm_info("APB_MDRV",
              $sformatf("完成: %s", item.convert2string()), UVM_HIGH)

    // 返回 IDLE
    #1;
    bus_idle();
  endtask

  // -------------------------------------------------------------------------
  // 总线 IDLE 状态
  // -------------------------------------------------------------------------
  task bus_idle();
    vif.PSEL    = 0;
    vif.PENABLE = 0;
    vif.PADDR   = '0;
    vif.PWRITE  = 0;
    vif.PWDATA  = '0;
    vif.PPROT   = '0;
    vif.PSTRB   = '0;
  endtask

endclass : apb_master_driver
