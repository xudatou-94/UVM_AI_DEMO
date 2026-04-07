// =============================================================================
// apb_slave_driver.sv - APB Slave Driver（TLM FIFO 版本）
//
// 设计说明：
//   原版本继承 uvm_driver，通过 seq_item_port.put/get 与 sequencer 通信。
//   该方式存在根本性设计缺陷：uvm_seq_item_pull_port 的设计语义是
//   "sequencer 产生激励 → driver 拉取"，而 APB slave 的激励来自总线
//   （DUT 是 master），方向相反，导致 put/get 调用在标准 sequencer 上挂起。
//
//   修正方案（TLM FIFO 双向通信）：
//     driver 改继承 uvm_component，去掉 seq_item_port；
//     新增一对 TLM blocking port：
//       req_port（put）: driver 将观察到的总线请求推送给 slave sequence
//       rsp_port（get）: driver 从 slave sequence 获取响应数据
//     两个 port 在 apb_agent.connect_phase 中连接到
//     apb_agent 内部的 req_fifo / rsp_fifo。
//
// 时序：
//   1. 检测到 SETUP 阶段（PSEL=1, PENABLE=0），锁存地址/控制信号
//   2. req_port.put(req) → 推送给 slave sequence
//   3. rsp_port.get(rsp) → 等待 slave sequence 返回响应
//   4. 进入 ACCESS 阶段后插入 wait_states 个等待周期
//   5. 驱动 PRDATA / PREADY / PSLVERR
// =============================================================================

class apb_slave_driver extends uvm_component;
  `uvm_component_utils(apb_slave_driver)

  // -------------------------------------------------------------------------
  // 接口句柄
  // -------------------------------------------------------------------------
  virtual apb_if vif;

  // -------------------------------------------------------------------------
  // TLM blocking port：与 apb_agent 内部 FIFO 连接
  //   req_port: driver → slave sequence（推送总线观察到的请求）
  //   rsp_port: slave sequence → driver（获取响应数据）
  // -------------------------------------------------------------------------
  uvm_blocking_put_port #(apb_seq_item) req_port;
  uvm_blocking_get_port #(apb_seq_item) rsp_port;

  // -------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "apb_slave_driver: 未获取到 virtual apb_if")
    req_port = new("req_port", this);
    rsp_port = new("rsp_port", this);
  endfunction

  // -------------------------------------------------------------------------
  // run_phase
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    vif.PRDATA  = '0;
    vif.PREADY  = 1'b1;
    vif.PSLVERR = 1'b0;

    @(posedge vif.PRESETn);

    forever begin
      @(posedge vif.PCLK);
      if (vif.PSEL && !vif.PENABLE)
        respond_to_transfer();
    end
  endtask

  // -------------------------------------------------------------------------
  // respond_to_transfer：单次 APB 事务响应
  // -------------------------------------------------------------------------
  task respond_to_transfer();
    apb_seq_item req, rsp;

    // SETUP 阶段：锁存总线信号，构造请求 item
    req = apb_seq_item::type_id::create("req");
    req.addr  = vif.PADDR;
    req.rw    = vif.PWRITE;
    req.wdata = vif.PWDATA;
    req.pprot = vif.PPROT;
    req.pstrb = vif.PSTRB;

    // 将请求推送给 slave sequence（通过 req_fifo）
    req_port.put(req);

    // 等待 slave sequence 返回响应（通过 rsp_fifo）
    rsp_port.get(rsp);

    // 进入 ACCESS 阶段（等待 PENABLE 拉高）
    // @(posedge vif.PCLK);  // 暂时注释，时序待确认

    // 插入等待状态：PREADY=0
    if (rsp.wait_states > 0) begin
      #1;
      vif.PREADY = 1'b0;
      repeat(rsp.wait_states - 1) @(posedge vif.PCLK);
      @(posedge vif.PCLK);
    end

    // 驱动响应信号
    #1;
    vif.PREADY  = 1'b1;
    vif.PSLVERR = rsp.pslverr;
    if (!vif.PWRITE)
      vif.PRDATA = rsp.rdata;

    `uvm_info("APB_SDRV",
      $sformatf("响应: addr=0x%08x rw=%0b rdata=0x%08x pslverr=%0b ws=%0d",
                req.addr, req.rw, vif.PRDATA, vif.PSLVERR, rsp.wait_states),
      UVM_HIGH)

    // 等待事务完成后复位信号
    @(posedge vif.PCLK);
    #1;
    if (!vif.PSEL) begin
      vif.PREADY  = 1'b1;
      vif.PRDATA  = '0;
      vif.PSLVERR = 1'b0;
    end
  endtask

endclass : apb_slave_driver
