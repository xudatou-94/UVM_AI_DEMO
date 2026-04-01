// =============================================================================
// axi_monitor.sv  AXI4 总线监控器
//
// 被动监听 AXI 总线，重建完整事务并通过 analysis port 广播：
//   - ap_write：完整写事务（AW + W + B）
//   - ap_read ：完整读事务（AR + R）
//
// outstanding 支持：同时跟踪多笔飞行中事务（by ID）
// =============================================================================
class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  import axi_pkg::*;

  // ---- 接口 ----
  virtual axi_if.monitor_mp vif;

  // ---- Analysis Ports ----
  uvm_analysis_port #(axi_seq_item) ap_write;
  uvm_analysis_port #(axi_seq_item) ap_read;

  // ---- 飞行中事务 ----
  axi_seq_item wr_inflight[logic [7:0]];  // awid → item（AW 到达后建立）
  axi_seq_item rd_inflight[logic [7:0]];  // arid → item（AR 到达后建立）

  // ---- W 数据收集 ----
  // 简化：按 AW 到达顺序（保序队列），每次只处理队首写事务的 W 数据
  logic [7:0]  aw_order_q[$];             // 保序的 awid 队列
  int          wr_beat_cnt[logic [7:0]];  // 每笔写已收到的 W beat 数

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_write = new("ap_write", this);
    ap_read  = new("ap_read",  this);
    if (!uvm_config_db #(virtual axi_if.monitor_mp)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "axi_monitor: vif not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    @(posedge vif.aresetn);
    @(posedge vif.aclk);

    fork
      monitor_aw_channel();
      monitor_w_channel();
      monitor_b_channel();
      monitor_ar_channel();
      monitor_r_channel();
    join
  endtask

  // ---------------------------------------------------------------------------
  // 监听 AW 通道
  // ---------------------------------------------------------------------------
  task monitor_aw_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.awvalid && vif.awready) begin
        axi_seq_item item = axi_seq_item::type_id::create("aw_mon");
        item.txn_type = AXI_WRITE;
        item.awid     = vif.awid;
        item.awaddr   = vif.awaddr;
        item.awlen    = vif.awlen;
        item.awsize   = vif.awsize;
        item.awburst  = axi_burst_e'(vif.awburst);
        item.wdata    = new[item.awlen + 1];
        item.wstrb    = new[item.awlen + 1];
        wr_inflight[item.awid] = item;
        aw_order_q.push_back(item.awid);
        wr_beat_cnt[item.awid] = 0;
        `uvm_info("MON_AW",
          $sformatf("AW: id=%0h addr=%0h len=%0d", item.awid, item.awaddr, item.awlen),
          UVM_HIGH)
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // 监听 W 通道
  // ---------------------------------------------------------------------------
  task monitor_w_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.wvalid && vif.wready) begin
        // W 通道没有 ID，按 AW 保序队列对应第一个 inflight 事务
        if (aw_order_q.size() > 0) begin
          logic [7:0]  cur_id = aw_order_q[0];
          if (wr_inflight.exists(cur_id)) begin
            axi_seq_item item = wr_inflight[cur_id];
            int beat = wr_beat_cnt[cur_id];
            if (beat <= item.awlen) begin
              item.wdata[beat] = vif.wdata;
              item.wstrb[beat] = vif.wstrb;
              wr_beat_cnt[cur_id]++;
            end
            // WLAST：写数据收集完毕
            if (vif.wlast) begin
              void'(aw_order_q.pop_front());
            end
          end
        end
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // 监听 B 通道
  // ---------------------------------------------------------------------------
  task monitor_b_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.bvalid && vif.bready) begin
        logic [7:0] bid_val = vif.bid;
        if (wr_inflight.exists(bid_val)) begin
          axi_seq_item item = wr_inflight[bid_val];
          item.bresp = axi_resp_e'(vif.bresp);
          wr_inflight.delete(bid_val);
          wr_beat_cnt.delete(bid_val);
          ap_write.write(item);
          `uvm_info("MON_B",
            $sformatf("B: id=%0h resp=%s addr=%0h",
              bid_val, item.bresp.name(), item.awaddr),
            UVM_HIGH)
        end
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // 监听 AR 通道
  // ---------------------------------------------------------------------------
  task monitor_ar_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.arvalid && vif.arready) begin
        axi_seq_item item = axi_seq_item::type_id::create("ar_mon");
        item.txn_type = AXI_READ;
        item.arid     = vif.arid;
        item.araddr   = vif.araddr;
        item.arlen    = vif.arlen;
        item.arsize   = vif.arsize;
        item.arburst  = axi_burst_e'(vif.arburst);
        item.rdata    = new[item.arlen + 1];
        item.rresp    = new[item.arlen + 1];
        rd_inflight[item.arid] = item;
        `uvm_info("MON_AR",
          $sformatf("AR: id=%0h addr=%0h len=%0d", item.arid, item.araddr, item.arlen),
          UVM_HIGH)
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // 监听 R 通道
  // ---------------------------------------------------------------------------
  task monitor_r_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.rvalid && vif.rready) begin
        logic [7:0] rid_val = vif.rid;
        if (rd_inflight.exists(rid_val)) begin
          axi_seq_item item = rd_inflight[rid_val];
          // 找到当前 beat 索引（已填充数量）
          int beat = 0;
          for (int i = 0; i <= item.arlen; i++)
            if (item.rdata[i] !== 'x) beat = i + 1;
          if (beat <= item.arlen) begin
            item.rdata[beat] = vif.rdata;
            item.rresp[beat] = axi_resp_e'(vif.rresp);
          end
          if (vif.rlast) begin
            rd_inflight.delete(rid_val);
            ap_read.write(item);
            `uvm_info("MON_R",
              $sformatf("R: id=%0h addr=%0h len=%0d last_data=%0h",
                rid_val, item.araddr, item.arlen, vif.rdata),
              UVM_HIGH)
          end
        end
      end
    end
  endtask

endclass
