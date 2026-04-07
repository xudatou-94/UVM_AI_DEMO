// =============================================================================
// axi_master_driver.sv  AXI4 Master Driver
//
// Outstanding 实现方案（6 进程并发）：
//
//   feed_transactions ── 从 sequencer 取事务，写入内部 FIFO
//   ├── drive_aw_channel  ── 发送写地址，sem_aw 信号量限制 outstanding
//   ├── drive_w_channel   ── 发送写数据（等待 AW 先行）
//   ├── handle_b_channel  ── 接收写响应，回填 bresp，释放 outstanding 槽位
//   ├── drive_ar_channel  ── 发送读地址，sem_ar 信号量限制 outstanding
//   └── handle_r_channel  ── 接收读数据，回填 rdata/rresp，释放 outstanding 槽位
//
// 关键数据结构：
//   wr_pending_q[$]  — 等待 B 响应的写事务（indexed by awid）
//   rd_pending_q[$]  — 等待 R 数据的读事务（indexed by arid）
//   sem_wr / sem_rd  — 信号量，初始值 = max_outstanding
//
// =============================================================================
class axi_master_driver extends uvm_driver #(axi_seq_item);
  `uvm_component_utils(axi_master_driver)

  import axi_pkg::*;

  // ---- 接口句柄 ----
  virtual axi_if.master_mp vif;

  // ---- 配置 ----
  axi_agent_cfg cfg;

  // ---- outstanding 控制 ----
  semaphore sem_wr;   // 写事务 outstanding 槽位
  semaphore sem_rd;   // 读事务 outstanding 槽位

  // ---- 内部 FIFO（feed → channel drivers）----
  axi_seq_item wr_item_q[$];   // 待发送写地址队列
  axi_seq_item rd_item_q[$];   // 待发送读地址队列

  // ---- 飞行中的事务（id → item）----
  axi_seq_item wr_inflight[logic [7:0]];   // awid → item
  axi_seq_item rd_inflight[logic [7:0]];   // arid → item

  // ---- 完成通知 ----
  // 通过 event 通知 feed 进程事务完成，以便 item_done
  event         wr_done_ev[logic [7:0]];
  event         rd_done_ev[logic [7:0]];

  // ---- W 通道同步：AW 发出后才允许发 W ----
  // awid_sent_q 记录已发送 AW 的 id，drive_w 等待后弹出
  logic [7:0]   awid_sent_q[$];
  semaphore     w_gate;   // 每发一个 AW 放一个 token，drive_w 每笔取一个

  function new(string name, uvm_component parent);
    super.new(name, parent);
    w_gate = new(0);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_if.master_mp)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "axi_master_driver: vif not found in config_db")
    if (!uvm_config_db #(axi_agent_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = new("cfg");
      `uvm_info("CFG", "axi_master_driver: using default cfg", UVM_LOW)
    end
    sem_wr = new(cfg.max_outstanding);
    sem_rd = new(cfg.max_outstanding);
  endfunction

  task run_phase(uvm_phase phase);
    // 初始化总线
    drv_reset();
    @(posedge vif.aresetn);
    @(posedge vif.aclk);

    // 6 个并发进程
    fork
      feed_transactions();
      drive_aw_channel();
      drive_w_channel();
      handle_b_channel();
      drive_ar_channel();
      handle_r_channel();
    join
  endtask

  // ---------------------------------------------------------------------------
  // 初始化信号
  // ---------------------------------------------------------------------------
  task drv_reset();
    vif.awvalid <= 0; vif.awid    <= 0; vif.awaddr  <= 0;
    vif.awlen   <= 0; vif.awsize  <= 0; vif.awburst <= 0;
    vif.awlock  <= 0; vif.awcache <= 0; vif.awprot  <= 0; vif.awqos <= 0;
    vif.wvalid  <= 0; vif.wdata   <= 0; vif.wstrb   <= 0; vif.wlast <= 0;
    vif.bready  <= 0;
    vif.arvalid <= 0; vif.arid    <= 0; vif.araddr  <= 0;
    vif.arlen   <= 0; vif.arsize  <= 0; vif.arburst <= 0;
    vif.arlock  <= 0; vif.arcache <= 0; vif.arprot  <= 0; vif.arqos <= 0;
    vif.rready  <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // feed_transactions: 从 sequencer 取事务，分发到写/读队列
  // ---------------------------------------------------------------------------
  task feed_transactions();
    forever begin
      axi_seq_item item;
      seq_item_port.get_next_item(item);
      if (item.txn_type == AXI_WRITE) begin
        wr_item_q.push_back(item);
        // 等待写事务完成（B 通道 done）
        wait (wr_done_ev.exists(item.awid));
        @(wr_done_ev[item.awid]);
        wr_done_ev.delete(item.awid);
      end else begin
        rd_item_q.push_back(item);
        // 等待读事务完成（R 通道 done）
        wait (rd_done_ev.exists(item.arid));
        @(rd_done_ev[item.arid]);
        rd_done_ev.delete(item.arid);
      end
      seq_item_port.item_done();
    end
  endtask

  // ---------------------------------------------------------------------------
  // drive_aw_channel: 消费 wr_item_q，驱动 AW 通道
  // ---------------------------------------------------------------------------
  task drive_aw_channel();
    forever begin
      axi_seq_item item;
      // 等待队列非空
      wait (wr_item_q.size() > 0);
      item = wr_item_q.pop_front();
      // 申请 outstanding 槽位
      sem_wr.get(1);
      // 登记飞行中事务
      wr_inflight[item.awid] = item;
      // 驱动 AW
      @(posedge vif.aclk);
      vif.awvalid <= 1;
      vif.awid    <= item.awid;
      vif.awaddr  <= item.awaddr;
      vif.awlen   <= item.awlen;
      vif.awsize  <= item.awsize;
      vif.awburst <= item.awburst;
      vif.awlock  <= 0;
      vif.awcache <= 0;
      vif.awprot  <= 0;
      vif.awqos   <= 0;
      // 等待 AWREADY 握手
      do @(posedge vif.aclk); while (!vif.awready);
      vif.awvalid <= 0;
      // 通知 W 通道可以发 W beat
      awid_sent_q.push_back(item.awid);
      w_gate.put(1);
    end
  endtask

  // ---------------------------------------------------------------------------
  // drive_w_channel: 等待 AW 发送后，驱动 W 通道（支持 burst）
  // ---------------------------------------------------------------------------
  task drive_w_channel();
    forever begin
      logic [7:0] awid;
      axi_seq_item item;
      // 等待 AW 已发出的通知
      w_gate.get(1);
      awid = awid_sent_q.pop_front();
      // 此时 wr_inflight[awid] 一定存在
      item = wr_inflight[awid];
      // 逐 beat 发送 W 数据
      for (int beat = 0; beat <= item.awlen; beat++) begin
        // WREADY 反压等待
        apply_bp_delay(item.wready_bp_mode, item.wready_bp_fixed,
                       item.wready_bp_min,  item.wready_bp_max);
        @(posedge vif.aclk);
        vif.wvalid <= 1;
        vif.wdata  <= item.wdata[beat];
        vif.wstrb  <= item.wstrb[beat];
        vif.wlast  <= (beat == item.awlen) ? 1'b1 : 1'b0;
        do @(posedge vif.aclk); while (!vif.wready);
      end
      vif.wvalid <= 0;
      vif.wlast  <= 0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // handle_b_channel: 接收 B 响应，回填 bresp，释放 outstanding 槽
  // ---------------------------------------------------------------------------
  task handle_b_channel();
    forever begin
      axi_seq_item item;
      logic [7:0]  bid_val;
      // BREADY 反压（在拉高 bready 前等待）
      @(posedge vif.aclk);
      // 等待 BVALID
      while (!vif.bvalid) @(posedge vif.aclk);
      bid_val = vif.bid;
      // 应用 BREADY 反压（已知是哪个事务 —— 通过 bid 查找）
      if (wr_inflight.exists(bid_val)) begin
        item = wr_inflight[bid_val];
        apply_bp_delay(item.bready_bp_mode, item.bready_bp_fixed,
                       item.bready_bp_min,  item.bready_bp_max);
      end
      vif.bready <= 1;
      @(posedge vif.aclk);  // 采样握手
      vif.bready <= 0;
      // 回填响应
      if (wr_inflight.exists(bid_val)) begin
        item = wr_inflight[bid_val];
        item.bresp = axi_resp_e'(vif.bresp);
        wr_inflight.delete(bid_val);
        // 通知 feed 进程
        wr_done_ev[bid_val] = wr_done_ev[bid_val];  // ensure exists
        ->wr_done_ev[bid_val];
        // 释放 outstanding 槽位
        sem_wr.put(1);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // drive_ar_channel: 消费 rd_item_q，驱动 AR 通道
  // ---------------------------------------------------------------------------
  task drive_ar_channel();
    forever begin
      axi_seq_item item;
      wait (rd_item_q.size() > 0);
      item = rd_item_q.pop_front();
      sem_rd.get(1);
      rd_inflight[item.arid] = item;
      // 初始化 rdata/rresp 数组
      item.rdata = new[item.arlen + 1];
      item.rresp = new[item.arlen + 1];
      @(posedge vif.aclk);
      vif.arvalid <= 1;
      vif.arid    <= item.arid;
      vif.araddr  <= item.araddr;
      vif.arlen   <= item.arlen;
      vif.arsize  <= item.arsize;
      vif.arburst <= item.arburst;
      vif.arlock  <= 0;
      vif.arcache <= 0;
      vif.arprot  <= 0;
      vif.arqos   <= 0;
      do @(posedge vif.aclk); while (!vif.arready);
      vif.arvalid <= 0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // handle_r_channel: 接收 R 数据，回填 rdata/rresp，释放 outstanding 槽
  // ---------------------------------------------------------------------------
  task handle_r_channel();
    forever begin
      axi_seq_item item;
      logic [7:0]  rid_val;
      int          beat_idx;
      // RREADY 反压（每 beat 独立）
      @(posedge vif.aclk);
      while (!vif.rvalid) @(posedge vif.aclk);
      rid_val = vif.rid;
      if (rd_inflight.exists(rid_val)) begin
        item = rd_inflight[rid_val];
        // 确定当前是第几拍（通过已接收数量推算）
        beat_idx = 0;
        foreach (item.rdata[i])
          if (item.rdata[i] !== 'x) beat_idx = i + 1;
        // RREADY 反压
        apply_bp_delay(item.rready_bp_mode, item.rready_bp_fixed,
                       item.rready_bp_min,  item.rready_bp_max);
        vif.rready <= 1;
        @(posedge vif.aclk);
        vif.rready <= 0;
        // 回填
        if (beat_idx < (item.arlen + 1)) begin
          item.rdata[beat_idx] = vif.rdata;
          item.rresp[beat_idx] = axi_resp_e'(vif.rresp);
        end
        // RLAST：事务完成
        if (vif.rlast) begin
          rd_inflight.delete(rid_val);
          ->rd_done_ev[rid_val];
          sem_rd.put(1);
        end
      end else begin
        // 没有对应事务，简单消费
        vif.rready <= 1;
        @(posedge vif.aclk);
        vif.rready <= 0;
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // 反压等待辅助函数
  // ---------------------------------------------------------------------------
  task apply_bp_delay(
    input axi_bp_mode_e mode,
    input int unsigned  fixed_cyc,
    input int unsigned  min_cyc,
    input int unsigned  max_cyc
  );
    int unsigned delay;
    case (mode)
      AXI_BP_NONE:  return;
      AXI_BP_FIXED: delay = fixed_cyc;
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
