// =============================================================================
// apb_slave_driver.sv - APB Slave Driver
//
// 功能：
//   被动响应 APB master 的访问，根据 sequence 提供的数据和延迟配置
//   驱动 PRDATA / PREADY / PSLVERR。
//
// 工作模式：
//   sequence 通过 put_port / get 提供响应，若无 sequence 驱动则使用默认值。
//   slave driver 检测到 PSEL 有效后，通过 seq_item_port 请求响应数据。
//
// 时序：
//   1. 检测到 PSEL 上升沿（SETUP 阶段）
//   2. 向 sequencer 获取响应 item（含 wait_states / pslverr / rdata）
//   3. 等待 wait_states 周期（PREADY=0）
//   4. 拉高 PREADY，驱动 PRDATA / PSLVERR
// =============================================================================

class apb_slave_driver extends uvm_driver #(apb_seq_item);
  `uvm_component_utils(apb_slave_driver)

  virtual apb_if vif;
  apb_agent_cfg  cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "apb_slave_driver: 未获取到 virtual apb_if")
    if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = apb_agent_cfg::type_id::create("cfg");
    end
  endfunction

  // -------------------------------------------------------------------------
  // run_phase：初始化 slave 输出，循环响应 master 事务
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    // 初始化 slave 输出
    vif.PRDATA  = '0;
    vif.PREADY  = 1;   // 默认 ready（无等待状态）
    vif.PSLVERR = 0;

    @(posedge vif.PRESETn);

    forever begin
      // 等待 SETUP 阶段（PSEL=1, PENABLE=0）
      @(posedge vif.PCLK);
      if (vif.PSEL && !vif.PENABLE) begin
        respond_to_transfer();
      end
    end
  endtask

  // -------------------------------------------------------------------------
  // 响应单次 APB 事务
  // -------------------------------------------------------------------------
  task respond_to_transfer();
    apb_seq_item req, rsp;
    int unsigned ws;

    // 构造请求 item（包含 master 的地址/写数据信息，供 sequence 参考）
    req = apb_seq_item::type_id::create("req");
    req.addr  = vif.PADDR;
    req.rw    = vif.PWRITE;
    req.wdata = vif.PWDATA;
    req.pprot = vif.PPROT;
    req.pstrb = vif.PSTRB;

    // 向 sequencer 请求响应（sequence 可自定义 rdata / wait_states / pslverr）
    seq_item_port.put(req);
    seq_item_port.get(rsp);

    ws = (rsp != null) ? rsp.wait_states : cfg.default_wait_states;

    // 等待 PENABLE（ACCESS 阶段开始）
    @(posedge vif.PCLK);

    // 插入等待状态（PREADY=0）
    if (ws > 0) begin
      #1;
      vif.PREADY = 0;
      repeat(ws - 1) @(posedge vif.PCLK);
      @(posedge vif.PCLK);
    end

    // 驱动响应
    #1;
    vif.PREADY  = 1;
    if (!vif.PWRITE) begin
      vif.PRDATA = (rsp != null) ? rsp.rdata : '0;
    end
    vif.PSLVERR = (rsp != null) ? rsp.pslverr : cfg.default_pslverr;

    `uvm_info("APB_SDRV",
              $sformatf("响应: addr=0x%08x rw=%0b rdata=0x%08x pslverr=%0b ws=%0d",
                        req.addr, req.rw,
                        vif.PRDATA, vif.PSLVERR, ws), UVM_HIGH)

    // 等待事务结束
    @(posedge vif.PCLK);
    #1;
    // 若 master 不再发起新事务，恢复默认
    if (!vif.PSEL) begin
      vif.PREADY  = 1;
      vif.PRDATA  = '0;
      vif.PSLVERR = 0;
    end
  endtask

endclass : apb_slave_driver
