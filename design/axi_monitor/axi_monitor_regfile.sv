// =============================================================================
// axi_monitor_regfile.sv
// APB 寄存器文件：软件配置/状态读写接口
//
// 寄存器地址映射（APB 地址 12bit）：
//
// PMU 区域（0x000 ~ 0x01C）：
//   0x000  PMU_CTRL       [0]=pmu_en（RW）
//   0x004  PMU_PERIOD     [31:0]（RW，默认 1000）
//   0x008  PMU_AW_CNT     [31:0]（RO，AW 通道快照）
//   0x00C  PMU_W_CNT      [31:0]（RO，W  通道快照）
//   0x010  PMU_B_CNT      [31:0]（RO，B  通道快照）
//   0x014  PMU_AR_CNT     [31:0]（RO，AR 通道快照）
//   0x018  PMU_R_CNT      [31:0]（RO，R  通道快照）
//
// Trace 区域（0x100 ~ 0x128）：
//   0x100  TRACE_CTRL     [0]=trace_en（RW），[1]=trace_clr（W1P，自清）
//   0x104  TRACE_COND_FIELD [2:0]（RW）
//   0x108  TRACE_COND_OP    [2:0]（RW）
//   0x10C  TRACE_COND_VAL   [31:0]（RW）
//   0x110  TRACE_STATUS   [0]=empty，[6:1]=count，[7]=full（RO）
//   0x114  TRACE_RD_CMD   [0]=rd_req（W1P，自清）
//   0x118  TRACE_RD_ADDR  [31:0]（RO）
//   0x11C  TRACE_RD_DATA  [31:0]（RO）
//   0x120  TRACE_RD_ID    [7:0]（RO）
//   0x124  TRACE_RD_BURST [1:0]（RO）
//   0x128  TRACE_RD_OSD   [7:0]（RO，outstanding）
// =============================================================================
module axi_monitor_regfile
  import axi_monitor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  // APB Slave 接口
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [11:0] paddr,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // PMU 配置输出
  output logic        pmu_en,
  output logic [31:0] pmu_period,

  // PMU 状态输入（来自 PMU 模块快照寄存器）
  input  logic [PMU_CNT_W-1:0] snap_aw_cnt,
  input  logic [PMU_CNT_W-1:0] snap_w_cnt,
  input  logic [PMU_CNT_W-1:0] snap_b_cnt,
  input  logic [PMU_CNT_W-1:0] snap_ar_cnt,
  input  logic [PMU_CNT_W-1:0] snap_r_cnt,

  // Trace 配置输出
  output logic          trace_en,
  output logic          trace_clr,
  output trace_field_e  cond_field,
  output trace_op_e     cond_op,
  output logic [31:0]   cond_val,

  // Trace 状态输入（来自 Trace 模块）
  input  logic                   sram_empty,
  input  logic [TRACE_PTR_W:0]   sram_count,
  input  logic                   sram_full,
  input  trace_entry_t           rd_entry,

  // Trace 读出命令
  output logic rd_req
);

  // -------------------------------------------------------------------------
  // 寄存器地址常量
  // -------------------------------------------------------------------------
  localparam logic [11:0] PMU_CTRL         = 12'h000;
  localparam logic [11:0] PMU_PERIOD       = 12'h004;
  localparam logic [11:0] PMU_AW_CNT       = 12'h008;
  localparam logic [11:0] PMU_W_CNT        = 12'h00C;
  localparam logic [11:0] PMU_B_CNT        = 12'h010;
  localparam logic [11:0] PMU_AR_CNT       = 12'h014;
  localparam logic [11:0] PMU_R_CNT        = 12'h018;

  localparam logic [11:0] TRACE_CTRL       = 12'h100;
  localparam logic [11:0] TRACE_COND_FIELD = 12'h104;
  localparam logic [11:0] TRACE_COND_OP    = 12'h108;
  localparam logic [11:0] TRACE_COND_VAL   = 12'h10C;
  localparam logic [11:0] TRACE_STATUS     = 12'h110;
  localparam logic [11:0] TRACE_RD_CMD     = 12'h114;
  localparam logic [11:0] TRACE_RD_ADDR    = 12'h118;
  localparam logic [11:0] TRACE_RD_DATA    = 12'h11C;
  localparam logic [11:0] TRACE_RD_ID      = 12'h120;
  localparam logic [11:0] TRACE_RD_BURST   = 12'h124;
  localparam logic [11:0] TRACE_RD_OSD     = 12'h128;

  // -------------------------------------------------------------------------
  // APB 写/读使能（ACCESS 相）
  // -------------------------------------------------------------------------
  logic apb_wr, apb_rd;
  assign apb_wr = psel & penable &  pwrite;
  assign apb_rd = psel & penable & ~pwrite;

  // -------------------------------------------------------------------------
  // 可写寄存器
  // -------------------------------------------------------------------------
  logic        r_pmu_en;
  logic [31:0] r_pmu_period;
  logic        r_trace_en;
  logic        r_trace_clr;    // W1P 自清
  logic [2:0]  r_cond_field;
  logic [2:0]  r_cond_op;
  logic [31:0] r_cond_val;
  logic        r_rd_req;       // W1P 自清

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_pmu_en     <= 1'b0;
      r_pmu_period <= 32'd1000;
      r_trace_en   <= 1'b0;
      r_trace_clr  <= 1'b0;
      r_cond_field <= '0;
      r_cond_op    <= '0;
      r_cond_val   <= '0;
      r_rd_req     <= 1'b0;
    end else begin
      // W1P 自清（优先级低于 APB 写）
      r_trace_clr <= 1'b0;
      r_rd_req    <= 1'b0;

      if (apb_wr) begin
        case (paddr)
          PMU_CTRL:         r_pmu_en     <= pwdata[0];
          PMU_PERIOD:       r_pmu_period <= pwdata;
          TRACE_CTRL: begin
                            r_trace_en  <= pwdata[0];
                            r_trace_clr <= pwdata[1];  // 下一拍自清
          end
          TRACE_COND_FIELD: r_cond_field <= pwdata[2:0];
          TRACE_COND_OP:    r_cond_op    <= pwdata[2:0];
          TRACE_COND_VAL:   r_cond_val   <= pwdata;
          TRACE_RD_CMD:     r_rd_req     <= pwdata[0];  // 下一拍自清
          default: ;
        endcase
      end
    end
  end

  // -------------------------------------------------------------------------
  // 寄存器读
  // -------------------------------------------------------------------------
  always_comb begin
    prdata = '0;
    case (paddr)
      PMU_CTRL:         prdata = {31'b0, r_pmu_en};
      PMU_PERIOD:       prdata = r_pmu_period;
      PMU_AW_CNT:       prdata = snap_aw_cnt;
      PMU_W_CNT:        prdata = snap_w_cnt;
      PMU_B_CNT:        prdata = snap_b_cnt;
      PMU_AR_CNT:       prdata = snap_ar_cnt;
      PMU_R_CNT:        prdata = snap_r_cnt;
      TRACE_CTRL:       prdata = {30'b0, r_trace_clr, r_trace_en};
      TRACE_COND_FIELD: prdata = {29'b0, r_cond_field};
      TRACE_COND_OP:    prdata = {29'b0, r_cond_op};
      TRACE_COND_VAL:   prdata = r_cond_val;
      TRACE_STATUS:     prdata = {24'b0, sram_full, sram_count, sram_empty};
      TRACE_RD_CMD:     prdata = {31'b0, r_rd_req};
      TRACE_RD_ADDR:    prdata = rd_entry.addr;
      TRACE_RD_DATA:    prdata = rd_entry.data;
      TRACE_RD_ID:      prdata = {24'b0, rd_entry.id};
      TRACE_RD_BURST:   prdata = {30'b0, rd_entry.burst};
      TRACE_RD_OSD:     prdata = {24'b0, rd_entry.outstanding};
      default:          prdata = '0;
    endcase
  end

  // APB 无等待状态，无错误
  assign pready  = 1'b1;
  assign pslverr = 1'b0;

  // -------------------------------------------------------------------------
  // 输出连接
  // -------------------------------------------------------------------------
  assign pmu_en    = r_pmu_en;
  assign pmu_period= r_pmu_period;
  assign trace_en  = r_trace_en;
  assign trace_clr = r_trace_clr;
  assign cond_field= trace_field_e'(r_cond_field);
  assign cond_op   = trace_op_e'(r_cond_op);
  assign cond_val  = r_cond_val;
  assign rd_req    = r_rd_req;

endmodule
