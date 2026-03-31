// =============================================================================
// axi_ch_cdc.sv
// 单通道 AXI 事件跨时钟同步模块
//
// 将 src_clk 域的 AXI 握手事件同步到 dst_clk（trace_clk）域。
// 每个通道（AW/W/B/AR/R）独立使用 Toggle 同步器：
//   1. src_clk：握手发生时捕获数据，翻转 req_toggle
//   2. dst_clk：3FF 同步 req_toggle，边沿检测产生单周期 event 脉冲，
//               同拍锁存捕获数据到 dst_clk 寄存器
//
// 限制说明：
//   若 src_clk 连续两拍发生握手（back-to-back），第二笔数据可能覆盖
//   捕获寄存器，导致第一笔事件在 dst 侧读到第二笔数据。
//   对于调试/监控用途此行为可接受；如需无损捕获应使用异步 FIFO。
// =============================================================================
module axi_ch_cdc
  import axi_monitor_pkg::*;
(
  input  logic src_clk,
  input  logic dst_clk,
  input  logic rst_n,

  // AXI 输入（src_clk 域）
  input  logic [AXI_ADDR_W-1:0] awaddr,
  input  logic [AXI_ID_W-1:0]   awid,
  input  logic [1:0]             awburst,
  input  logic                   awvalid,
  input  logic                   awready,

  input  logic [AXI_DATA_W-1:0] wdata,
  input  logic                   wvalid,
  input  logic                   wready,

  input  logic                   bvalid,
  input  logic                   bready,

  input  logic [AXI_ADDR_W-1:0] araddr,
  input  logic [AXI_ID_W-1:0]   arid,
  input  logic [1:0]             arburst,
  input  logic                   arvalid,
  input  logic                   arready,

  input  logic [AXI_DATA_W-1:0] rdata,
  input  logic [AXI_ID_W-1:0]   rid,
  input  logic                   rvalid,
  input  logic                   rready,

  // 同步后事件输出（dst_clk 域）
  // *_event 为单周期脉冲，其余字段在 *_event 有效拍同步更新
  output axi_ch_events_t         events
);

  // =========================================================================
  // src_clk 域：握手检测 + 数据捕获 + Toggle
  // =========================================================================

  // 握手
  logic src_aw_hshk, src_w_hshk, src_b_hshk, src_ar_hshk, src_r_hshk;
  assign src_aw_hshk = awvalid & awready;
  assign src_w_hshk  = wvalid  & wready;
  assign src_b_hshk  = bvalid  & bready;
  assign src_ar_hshk = arvalid & arready;
  assign src_r_hshk  = rvalid  & rready;

  // AW 捕获 + toggle
  logic [AXI_ADDR_W-1:0] cap_aw_addr;
  logic [AXI_ID_W-1:0]   cap_aw_id;
  logic [1:0]             cap_aw_burst;
  logic                   aw_req_toggle;

  always_ff @(posedge src_clk or negedge rst_n) begin
    if (!rst_n) begin
      cap_aw_addr   <= '0;
      cap_aw_id     <= '0;
      cap_aw_burst  <= '0;
      aw_req_toggle <= 1'b0;
    end else if (src_aw_hshk) begin
      cap_aw_addr   <= awaddr;
      cap_aw_id     <= awid;
      cap_aw_burst  <= awburst;
      aw_req_toggle <= ~aw_req_toggle;
    end
  end

  // W 捕获 + toggle
  logic [AXI_DATA_W-1:0] cap_w_data;
  logic                   w_req_toggle;

  always_ff @(posedge src_clk or negedge rst_n) begin
    if (!rst_n) begin
      cap_w_data   <= '0;
      w_req_toggle <= 1'b0;
    end else if (src_w_hshk) begin
      cap_w_data   <= wdata;
      w_req_toggle <= ~w_req_toggle;
    end
  end

  // B toggle（无数据）
  logic b_req_toggle;
  always_ff @(posedge src_clk or negedge rst_n) begin
    if (!rst_n) b_req_toggle <= 1'b0;
    else if (src_b_hshk) b_req_toggle <= ~b_req_toggle;
  end

  // AR 捕获 + toggle
  logic [AXI_ADDR_W-1:0] cap_ar_addr;
  logic [AXI_ID_W-1:0]   cap_ar_id;
  logic [1:0]             cap_ar_burst;
  logic                   ar_req_toggle;

  always_ff @(posedge src_clk or negedge rst_n) begin
    if (!rst_n) begin
      cap_ar_addr   <= '0;
      cap_ar_id     <= '0;
      cap_ar_burst  <= '0;
      ar_req_toggle <= 1'b0;
    end else if (src_ar_hshk) begin
      cap_ar_addr   <= araddr;
      cap_ar_id     <= arid;
      cap_ar_burst  <= arburst;
      ar_req_toggle <= ~ar_req_toggle;
    end
  end

  // R 捕获 + toggle
  logic [AXI_DATA_W-1:0] cap_r_data;
  logic [AXI_ID_W-1:0]   cap_r_id;
  logic                   r_req_toggle;

  always_ff @(posedge src_clk or negedge rst_n) begin
    if (!rst_n) begin
      cap_r_data   <= '0;
      cap_r_id     <= '0;
      r_req_toggle <= 1'b0;
    end else if (src_r_hshk) begin
      cap_r_data   <= rdata;
      cap_r_id     <= rid;
      r_req_toggle <= ~r_req_toggle;
    end
  end

  // =========================================================================
  // dst_clk 域：3FF 同步器 + 边沿检测 + 数据锁存
  //
  // 使用 3FF（而非 2FF）以在高频 dst_clk 下提供更充裕的建立时间裕量。
  // =========================================================================

  // AW 同步
  logic [2:0] aw_sync_ff;
  logic       aw_sync_prev;
  logic       aw_edge;

  always_ff @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_sync_ff   <= '0;
      aw_sync_prev <= 1'b0;
    end else begin
      aw_sync_ff   <= {aw_sync_ff[1:0], aw_req_toggle};
      aw_sync_prev <= aw_sync_ff[2];
    end
  end
  assign aw_edge = aw_sync_ff[2] ^ aw_sync_prev;

  // W 同步
  logic [2:0] w_sync_ff;
  logic       w_sync_prev;
  logic       w_edge;

  always_ff @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      w_sync_ff   <= '0;
      w_sync_prev <= 1'b0;
    end else begin
      w_sync_ff   <= {w_sync_ff[1:0], w_req_toggle};
      w_sync_prev <= w_sync_ff[2];
    end
  end
  assign w_edge = w_sync_ff[2] ^ w_sync_prev;

  // B 同步
  logic [2:0] b_sync_ff;
  logic       b_sync_prev;
  logic       b_edge;

  always_ff @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      b_sync_ff   <= '0;
      b_sync_prev <= 1'b0;
    end else begin
      b_sync_ff   <= {b_sync_ff[1:0], b_req_toggle};
      b_sync_prev <= b_sync_ff[2];
    end
  end
  assign b_edge = b_sync_ff[2] ^ b_sync_prev;

  // AR 同步
  logic [2:0] ar_sync_ff;
  logic       ar_sync_prev;
  logic       ar_edge;

  always_ff @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      ar_sync_ff   <= '0;
      ar_sync_prev <= 1'b0;
    end else begin
      ar_sync_ff   <= {ar_sync_ff[1:0], ar_req_toggle};
      ar_sync_prev <= ar_sync_ff[2];
    end
  end
  assign ar_edge = ar_sync_ff[2] ^ ar_sync_prev;

  // R 同步
  logic [2:0] r_sync_ff;
  logic       r_sync_prev;
  logic       r_edge;

  always_ff @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      r_sync_ff   <= '0;
      r_sync_prev <= 1'b0;
    end else begin
      r_sync_ff   <= {r_sync_ff[1:0], r_req_toggle};
      r_sync_prev <= r_sync_ff[2];
    end
  end
  assign r_edge = r_sync_ff[2] ^ r_sync_prev;

  // =========================================================================
  // dst_clk 域：输出寄存器
  // *_event 与数据字段在同一拍锁存，保证 event 高电平时数据有效
  // =========================================================================
  axi_ch_events_t ev_r;

  always_ff @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      ev_r <= '0;
    end else begin
      // 默认 event 脉冲清零（单周期有效）
      ev_r.aw_event <= 1'b0;
      ev_r.w_event  <= 1'b0;
      ev_r.b_event  <= 1'b0;
      ev_r.ar_event <= 1'b0;
      ev_r.r_event  <= 1'b0;

      if (aw_edge) begin
        ev_r.aw_event <= 1'b1;
        ev_r.aw_addr  <= cap_aw_addr;
        ev_r.aw_id    <= cap_aw_id;
        ev_r.aw_burst <= cap_aw_burst;
      end

      if (w_edge) begin
        ev_r.w_event <= 1'b1;
        ev_r.w_data  <= cap_w_data;
      end

      if (b_edge)
        ev_r.b_event <= 1'b1;

      if (ar_edge) begin
        ev_r.ar_event <= 1'b1;
        ev_r.ar_addr  <= cap_ar_addr;
        ev_r.ar_id    <= cap_ar_id;
        ev_r.ar_burst <= cap_ar_burst;
      end

      if (r_edge) begin
        ev_r.r_event <= 1'b1;
        ev_r.r_data  <= cap_r_data;
        ev_r.r_id    <= cap_r_id;
      end
    end
  end

  assign events = ev_r;

endmodule
