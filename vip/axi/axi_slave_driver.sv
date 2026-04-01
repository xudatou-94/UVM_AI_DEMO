// =============================================================================
// axi_slave_driver.sv  AXI4 Slave Driver（响应式）
//
// 工作模式：
//   - 通过 TLM FIFO 从 slave sequencer 接收响应事务（axi_seq_item）
//   - 接收 AW+W 后，向上层（test/scoreboard）发送请求，等待响应回填
//   - 对写响应（B）和读响应（R）使用 seq_item 中的 s_bresp / s_rdata / s_rresp
//
// 进程结构：
//   recv_aw_channel   — 监听 AW，控制 AWREADY 反压
//   recv_w_channel    — 监听 W beat，控制 WREADY 反压，收集完整写数据
//   send_b_response   — 向 master 发 B 响应（取自 req_fifo）
//   recv_ar_channel   — 监听 AR，控制 ARREADY 反压
//   send_r_response   — 向 master 发 R 数据（取自 req_fifo）
//
// TLM 接口（由 axi_agent 连接）：
//   req_export  — agent 将 slave seq_item 推入此 FIFO
//   rsp_port    — driver 通过此 port 将已完成的事务发出（optional）
// =============================================================================
class axi_slave_driver extends uvm_driver #(axi_seq_item);
  `uvm_component_utils(axi_slave_driver)

  import axi_pkg::*;

  // ---- 接口句柄 ----
  virtual axi_if.slave_mp vif;

  // ---- 配置 ----
  axi_agent_cfg cfg;

  // ---- TLM FIFO：从 sequencer 接收响应 seq_item ----
  uvm_tlm_fifo #(axi_seq_item) req_fifo;  // 由 agent 连接

  // ---- 内部待响应队列 ----
  // AW 队列：key=awid，value=item（含地址，等待 W 数据填充）
  axi_seq_item aw_q[logic [7:0]];   // awid → item（进行中的写事务）
  axi_seq_item aw_order_q[$];       // 保序队列，记录 AW 到达顺序

  // AR 队列
  axi_seq_item ar_q[$];             // 已到达的读请求，等待响应

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_if.slave_mp)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "axi_slave_driver: vif not found in config_db")
    if (!uvm_config_db #(axi_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = new("cfg");
      `uvm_info("CFG", "axi_slave_driver: using default cfg", UVM_LOW)
    end
    req_fifo = new("req_fifo", this, 32);
  endfunction

  task run_phase(uvm_phase phase);
    drv_reset();
    @(posedge vif.aresetn);
    @(posedge vif.aclk);

    fork
      recv_aw_channel();
      recv_w_channel();
      send_b_response();
      recv_ar_channel();
      send_r_response();
    join
  endtask

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------
  task drv_reset();
    vif.awready <= 0;
    vif.wready  <= 0;
    vif.bid     <= 0; vif.bresp  <= 0; vif.bvalid <= 0;
    vif.arready <= 0;
    vif.rid     <= 0; vif.rdata  <= 0; vif.rresp  <= 0;
    vif.rlast   <= 0; vif.rvalid <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // recv_aw_channel：接受写地址，AWREADY 按 cfg 反压
  // ---------------------------------------------------------------------------
  task recv_aw_channel();
    forever begin
      axi_seq_item item;
      // AWREADY 反压延迟（全局配置）
      apply_bp_delay(cfg.awready_bp_mode, cfg.awready_bp_fixed,
                     cfg.awready_bp_min,  cfg.awready_bp_max);
      @(posedge vif.aclk);
      vif.awready <= 1;
      // 等待 AWVALID
      while (!vif.awvalid) @(posedge vif.aclk);
      // 握手成功，创建 item 记录地址
      item = axi_seq_item::type_id::create("aw_item");
      item.txn_type = AXI_WRITE;
      item.awid     = vif.awid;
      item.awaddr   = vif.awaddr;
      item.awlen    = vif.awlen;
      item.awsize   = vif.awsize;
      item.awburst  = axi_burst_e'(vif.awburst);
      item.wdata    = new[item.awlen + 1];
      item.wstrb    = new[item.awlen + 1];
      aw_q[item.awid] = item;
      aw_order_q.push_back(item);
      vif.awready <= 0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // recv_w_channel：接受写数据 beat，WREADY 按 seq_item 反压
  // ---------------------------------------------------------------------------
  task recv_w_channel();
    forever begin
      axi_seq_item item;
      int beat_idx;
      // 等待当前有 AW 待响应
      wait (aw_order_q.size() > 0);
      item      = aw_order_q[0];   // 当前正在接收 W 的事务（保序）
      beat_idx  = 0;
      // 接收所有 beat
      while (beat_idx <= item.awlen) begin
        // WREADY 反压（seq_item 中的配置）
        apply_bp_delay(item.wready_bp_mode, item.wready_bp_fixed,
                       item.wready_bp_min,  item.wready_bp_max);
        @(posedge vif.aclk);
        vif.wready <= 1;
        while (!vif.wvalid) @(posedge vif.aclk);
        // 握手
        item.wdata[beat_idx] = vif.wdata;
        item.wstrb[beat_idx] = vif.wstrb;
        vif.wready <= 0;
        beat_idx++;
      end
      // W 数据收集完毕，从保序队列移出
      void'(aw_order_q.pop_front());
      // 将完整写请求放入 sequencer（req_fifo 通过 seq_item_port 暴露给 sequencer）
      // slave driver 直接调用 get_next_item 获取响应，使用 req_fifo 间接通信
      // 此处：通知 send_b_response 可以发 B
      // 简化实现：直接把完整 item 推给 b_pending_q
      b_pending_q.push_back(item);
    end
  endtask

  // ---- B 响应等待队列（W 收集完后推入）----
  axi_seq_item b_pending_q[$];

  // ---------------------------------------------------------------------------
  // send_b_response：向 master 发 B 响应
  // ---------------------------------------------------------------------------
  task send_b_response();
    forever begin
      axi_seq_item req_item, rsp_item;
      // 等待有完整写请求
      wait (b_pending_q.size() > 0);
      req_item = b_pending_q.pop_front();
      // 从 sequencer 获取响应（包含 s_bresp）
      seq_item_port.get_next_item(rsp_item);
      // 发 B 通道
      @(posedge vif.aclk);
      vif.bvalid <= 1;
      vif.bid    <= req_item.awid;
      vif.bresp  <= rsp_item.s_bresp;
      // 等待 BREADY
      while (!vif.bready) @(posedge vif.aclk);
      vif.bvalid <= 0;
      seq_item_port.item_done();
    end
  endtask

  // ---------------------------------------------------------------------------
  // recv_ar_channel：接受读地址
  // ---------------------------------------------------------------------------
  task recv_ar_channel();
    forever begin
      axi_seq_item item;
      apply_bp_delay(cfg.arready_bp_mode, cfg.arready_bp_fixed,
                     cfg.arready_bp_min,  cfg.arready_bp_max);
      @(posedge vif.aclk);
      vif.arready <= 1;
      while (!vif.arvalid) @(posedge vif.aclk);
      item = axi_seq_item::type_id::create("ar_item");
      item.txn_type = AXI_READ;
      item.arid     = vif.arid;
      item.araddr   = vif.araddr;
      item.arlen    = vif.arlen;
      item.arsize   = vif.arsize;
      item.arburst  = axi_burst_e'(vif.arburst);
      ar_q.push_back(item);
      vif.arready <= 0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // send_r_response：向 master 发 R 数据
  // ---------------------------------------------------------------------------
  task send_r_response();
    forever begin
      axi_seq_item req_item, rsp_item;
      wait (ar_q.size() > 0);
      req_item = ar_q.pop_front();
      // 从 sequencer 获取响应（包含 s_rdata[] / s_rresp）
      seq_item_port.get_next_item(rsp_item);
      // 发送每个 R beat
      for (int beat = 0; beat <= req_item.arlen; beat++) begin
        @(posedge vif.aclk);
        vif.rvalid <= 1;
        vif.rid    <= req_item.arid;
        vif.rdata  <= (beat < rsp_item.s_rdata.size()) ?
                       rsp_item.s_rdata[beat] : 32'hDEAD_BEEF;
        vif.rresp  <= rsp_item.s_rresp;
        vif.rlast  <= (beat == req_item.arlen) ? 1'b1 : 1'b0;
        while (!vif.rready) @(posedge vif.aclk);
      end
      vif.rvalid <= 0;
      vif.rlast  <= 0;
      seq_item_port.item_done();
    end
  endtask

  // ---------------------------------------------------------------------------
  // 反压等待
  // ---------------------------------------------------------------------------
  task apply_bp_delay(
    input axi_bp_mode_e mode,
    input int unsigned  fixed_cyc,
    input int unsigned  min_cyc,
    input int unsigned  max_cyc
  );
    int unsigned delay;
    case (mode)
      AXI_BP_NONE:   return;
      AXI_BP_FIXED:  delay = fixed_cyc;
      AXI_BP_RANDOM: begin
        if (max_cyc > min_cyc)
          delay = $urandom_range(min_cyc, max_cyc);
        else
          delay = min_cyc;
      end
      default: return;
    endcase
    repeat (delay) @(posedge vif.aclk);
  endtask

endclass
