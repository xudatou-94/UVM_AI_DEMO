// =============================================================================
// axi_monitor_top.sv
// AXI Monitor 顶层：被动监控 AXI 总线，通过 APB 接口配置和读取结果
//
// 子模块：
//   u_regfile  - APB 寄存器文件，软件配置/状态读写
//   u_pmu      - PMU：周期性统计各通道握手次数
//   u_trace    - Trace：条件过滤，命中时写入 SRAM，支持软件读出
// =============================================================================
module axi_monitor_top
  import axi_monitor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  // ------------------------------------------------------------------
  // APB Slave 接口（软件配置通道）
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
  // AXI 总线监控输入（被动，只观测，不驱动）
  // ------------------------------------------------------------------
  // 写地址通道
  input  logic [AXI_ADDR_W-1:0] awaddr,
  input  logic [AXI_ID_W-1:0]   awid,
  input  logic [1:0]             awburst,
  input  logic                   awvalid,
  input  logic                   awready,

  // 写数据通道
  input  logic [AXI_DATA_W-1:0] wdata,
  input  logic                   wvalid,
  input  logic                   wready,

  // 写响应通道
  input  logic                   bvalid,
  input  logic                   bready,

  // 读地址通道
  input  logic [AXI_ADDR_W-1:0] araddr,
  input  logic [AXI_ID_W-1:0]   arid,
  input  logic [1:0]             arburst,
  input  logic                   arvalid,
  input  logic                   arready,

  // 读数据通道
  input  logic [AXI_DATA_W-1:0] rdata,
  input  logic [AXI_ID_W-1:0]   rid,
  input  logic                   rvalid,
  input  logic                   rready
);

  // -------------------------------------------------------------------------
  // 内部握手信号
  // -------------------------------------------------------------------------
  logic aw_hshk, w_hshk, b_hshk, ar_hshk, r_hshk;
  assign aw_hshk = awvalid & awready;
  assign w_hshk  = wvalid  & wready;
  assign b_hshk  = bvalid  & bready;
  assign ar_hshk = arvalid & arready;
  assign r_hshk  = rvalid  & rready;

  // -------------------------------------------------------------------------
  // PMU 配置 / 状态信号
  // -------------------------------------------------------------------------
  logic        pmu_en;
  logic [31:0] pmu_period;
  logic [PMU_CNT_W-1:0] snap_aw_cnt, snap_w_cnt, snap_b_cnt,
                         snap_ar_cnt, snap_r_cnt;

  // -------------------------------------------------------------------------
  // Trace 配置 / 状态信号
  // -------------------------------------------------------------------------
  logic          trace_en, trace_clr;
  trace_field_e  cond_field;
  trace_op_e     cond_op;
  logic [31:0]   cond_val;
  logic                   sram_empty;
  logic [TRACE_PTR_W:0]   sram_count;
  logic                   sram_full;
  trace_entry_t           rd_entry;
  logic                   rd_req;

  // -------------------------------------------------------------------------
  // 子模块例化
  // -------------------------------------------------------------------------

  // APB 寄存器文件
  axi_monitor_regfile u_regfile (
    .clk, .rst_n,
    .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr,
    .pmu_en, .pmu_period,
    .snap_aw_cnt, .snap_w_cnt, .snap_b_cnt, .snap_ar_cnt, .snap_r_cnt,
    .trace_en, .trace_clr, .cond_field, .cond_op, .cond_val,
    .sram_empty, .sram_count, .sram_full, .rd_entry, .rd_req
  );

  // PMU
  axi_monitor_pmu u_pmu (
    .clk, .rst_n,
    .pmu_en, .pmu_period,
    .aw_hshk, .w_hshk, .b_hshk, .ar_hshk, .r_hshk,
    .snap_aw_cnt, .snap_w_cnt, .snap_b_cnt, .snap_ar_cnt, .snap_r_cnt
  );

  // Trace
  axi_monitor_trace u_trace (
    .clk, .rst_n,
    .trace_en, .trace_clr,
    .cond_field, .cond_op, .cond_val,
    .awaddr, .awid, .awburst, .awvalid, .awready,
    .wdata,  .wvalid, .wready,
    .bvalid, .bready,
    .araddr, .arid, .arburst, .arvalid, .arready,
    .rdata,  .rid,  .rvalid, .rready,
    .sram_empty, .sram_count, .sram_full,
    .rd_req, .rd_entry
  );

endmodule
