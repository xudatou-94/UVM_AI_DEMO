// =============================================================================
// axi_monitor_top.sv
// AXI Monitor 顶层
//
// 时钟域说明：
//   clk       - APB 时钟 / PMU 时钟（监控 ch0）
//   trace_clk - Trace 模块时钟，应为所有 axi_clk 中频率最高者
//   axi_clk   - 每个 AXI 通道独立时钟，通过 axi_ch_cdc 同步到 trace_clk
//
// 子模块：
//   u_regfile         - APB 寄存器文件（clk 域）
//   u_pmu             - PMU，监控 ch0，工作在 clk 域
//   u_cdc[N_CH]       - 每通道 AXI 事件 CDC（axi_clk[i] → trace_clk）
//   u_trace           - Trace，工作在 trace_clk 域
// =============================================================================
module axi_monitor_top
  import axi_monitor_pkg::*;
(
  input  logic clk,        // APB / PMU 时钟
  input  logic rst_n,
  input  logic trace_clk,  // Trace 时钟（所有 axi_clk 中最高频）

  // ------------------------------------------------------------------
  // APB Slave 接口
  // ------------------------------------------------------------------
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [11:0] paddr,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // ------------------------------------------------------------------
  // N_CH 路 AXI 总线监控输入
  // 每路独立时钟 axi_clk[i]
  // ------------------------------------------------------------------
  input  logic [N_CH-1:0]                  axi_clk,

  // 写地址通道
  input  logic [N_CH-1:0][AXI_ADDR_W-1:0] awaddr,
  input  logic [N_CH-1:0][AXI_ID_W-1:0]   awid,
  input  logic [N_CH-1:0][1:0]             awburst,
  input  logic [N_CH-1:0]                  awvalid,
  input  logic [N_CH-1:0]                  awready,

  // 写数据通道
  input  logic [N_CH-1:0][AXI_DATA_W-1:0] wdata,
  input  logic [N_CH-1:0]                  wvalid,
  input  logic [N_CH-1:0]                  wready,

  // 写响应通道（ch0 额外引出 bresp 供 PMU 使用）
  input  logic [N_CH-1:0]                  bvalid,
  input  logic [N_CH-1:0]                  bready,
  input  logic [N_CH-1:0][1:0]             bresp,

  // 读地址通道
  input  logic [N_CH-1:0][AXI_ADDR_W-1:0] araddr,
  input  logic [N_CH-1:0][AXI_ID_W-1:0]   arid,
  input  logic [N_CH-1:0][1:0]             arburst,
  input  logic [N_CH-1:0]                  arvalid,
  input  logic [N_CH-1:0]                  arready,

  // 读数据通道
  input  logic [N_CH-1:0][AXI_DATA_W-1:0] rdata,
  input  logic [N_CH-1:0][AXI_ID_W-1:0]   rid,
  input  logic [N_CH-1:0]                  rvalid,
  input  logic [N_CH-1:0]                  rready,
  input  logic [N_CH-1:0][1:0]             rresp   // ch0 供 PMU 使用
);

  // =========================================================================
  // 内部信号
  // =========================================================================

  // PMU 配置 / 状态
  logic        pmu_en;
  logic [31:0] pmu_period;
  logic [PMU_CNT_W-1:0] snap_aw_cnt, snap_w_cnt, snap_b_cnt,
                         snap_ar_cnt, snap_r_cnt;
  logic [PMU_CNT_W-1:0] snap_b_err_cnt, snap_r_err_cnt;

  // Trace 配置 / 状态
  logic          trace_en,  trace_clr;
  trace_field_e  cond_field;
  trace_op_e     cond_op;
  logic [31:0]   cond_val;
  logic [N_CH_W-1:0] ch_sel;
  logic                   sram_empty;
  logic [TRACE_PTR_W:0]   sram_count;
  logic                   sram_full;
  trace_entry_t           rd_entry;
  logic                   rd_req;

  // CDC 模块输出（trace_clk 域，每通道一组）
  axi_ch_events_t ch_events [N_CH];

  // 选中通道事件（MUX 输出）
  axi_ch_events_t sel_events;

  // =========================================================================
  // APB 寄存器文件
  // =========================================================================
  axi_monitor_regfile u_regfile (
    .clk, .rst_n,
    .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr,
    .pmu_en, .pmu_period,
    .snap_aw_cnt, .snap_w_cnt, .snap_b_cnt, .snap_ar_cnt, .snap_r_cnt,
    .snap_b_err_cnt, .snap_r_err_cnt,
    .trace_en, .trace_clr, .cond_field, .cond_op, .cond_val, .ch_sel,
    .sram_empty, .sram_count, .sram_full, .rd_entry, .rd_req
  );

  // =========================================================================
  // PMU：监控 ch0，工作在 clk 域
  // 若 clk != axi_clk[0]，需在外部对 AXI 握手信号做同步处理
  // =========================================================================
  logic ch0_aw_hshk, ch0_w_hshk, ch0_b_hshk, ch0_ar_hshk, ch0_r_hshk;
  assign ch0_aw_hshk = awvalid[0] & awready[0];
  assign ch0_w_hshk  = wvalid[0]  & wready[0];
  assign ch0_b_hshk  = bvalid[0]  & bready[0];
  assign ch0_ar_hshk = arvalid[0] & arready[0];
  assign ch0_r_hshk  = rvalid[0]  & rready[0];

  axi_monitor_pmu u_pmu (
    .clk, .rst_n,
    .pmu_en, .pmu_period,
    .aw_hshk (ch0_aw_hshk),
    .w_hshk  (ch0_w_hshk),
    .b_hshk  (ch0_b_hshk),
    .ar_hshk (ch0_ar_hshk),
    .r_hshk  (ch0_r_hshk),
    .bresp   (bresp[0]),
    .rresp   (rresp[0]),
    .snap_aw_cnt, .snap_w_cnt, .snap_b_cnt, .snap_ar_cnt, .snap_r_cnt,
    .snap_b_err_cnt, .snap_r_err_cnt
  );

  // =========================================================================
  // N_CH 路 CDC：axi_clk[i] → trace_clk
  // =========================================================================
  generate
    for (genvar i = 0; i < N_CH; i++) begin : gen_cdc
      axi_ch_cdc u_cdc (
        .src_clk  (axi_clk[i]),
        .dst_clk  (trace_clk),
        .rst_n,
        .awaddr   (awaddr[i]),  .awid  (awid[i]),  .awburst (awburst[i]),
        .awvalid  (awvalid[i]), .awready(awready[i]),
        .wdata    (wdata[i]),   .wvalid (wvalid[i]), .wready  (wready[i]),
        .bvalid   (bvalid[i]),  .bready (bready[i]),
        .araddr   (araddr[i]),  .arid   (arid[i]),  .arburst (arburst[i]),
        .arvalid  (arvalid[i]),.arready(arready[i]),
        .rdata    (rdata[i]),   .rid    (rid[i]),
        .rvalid   (rvalid[i]),  .rready (rready[i]),
        .events   (ch_events[i])
      );
    end
  endgenerate

  // =========================================================================
  // 通道 MUX：根据 ch_sel 选择目标通道事件送入 Trace
  // ch_sel 在 clk 域，trace_clk 域读取（监控用途，接受 1~2 拍不确定性）
  // =========================================================================
  always_comb begin
    sel_events = ch_events[0];  // 默认 ch0
    for (int i = 0; i < N_CH; i++) begin
      if (N_CH_W'(i) == ch_sel)
        sel_events = ch_events[i];
    end
  end

  // =========================================================================
  // Trace 模块：工作在 trace_clk 域
  // =========================================================================
  axi_monitor_trace u_trace (
    .trace_clk,
    .rst_n,
    .trace_en, .trace_clr,
    .cond_field, .cond_op, .cond_val,
    .events    (sel_events),
    .sram_empty, .sram_count, .sram_full,
    .rd_req, .rd_entry
  );

endmodule
