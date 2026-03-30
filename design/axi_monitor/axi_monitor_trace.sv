// =============================================================================
// axi_monitor_trace.sv
// Trace 组件：按条件过滤 AXI 总线事务，命中时记录到片上 SRAM
//
// 条件字段：AW_ADDR / AR_ADDR / W_DATA / R_DATA / AW_ID / AR_ID / BURST
// 比较运算：== / != / > / < / >= / <=
//
// SRAM 记录内容：addr / data / id / burst / outstanding
// SRAM 状态：empty / count / full
// 读出：rd_req 脉冲将当前头部条目锁存到 rd_entry，读指针后移
// =============================================================================
module axi_monitor_trace
  import axi_monitor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  // 配置
  input  logic         trace_en,    // Trace 使能
  input  logic         trace_clr,   // SRAM 清空（单周期脉冲）
  input  trace_field_e cond_field,  // 条件字段选择
  input  trace_op_e    cond_op,     // 比较运算符
  input  logic [31:0]  cond_val,    // 比较基准值

  // AXI 监控输入（被动，不驱动任何信号）
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

  // SRAM 状态输出
  output logic                      sram_empty,
  output logic [TRACE_PTR_W:0]      sram_count,   // 0 ~ TRACE_DEPTH
  output logic                      sram_full,

  // 软件读出接口
  input  logic         rd_req,     // 读请求（单周期脉冲，来自寄存器）
  output trace_entry_t rd_entry    // 锁存的读出条目
);

  // -------------------------------------------------------------------------
  // AXI 握手信号
  // -------------------------------------------------------------------------
  logic aw_hshk, w_hshk, b_hshk, ar_hshk, r_hshk;
  assign aw_hshk = awvalid & awready;
  assign w_hshk  = wvalid  & wready;
  assign b_hshk  = bvalid  & bready;
  assign ar_hshk = arvalid & arready;
  assign r_hshk  = rvalid  & rready;

  // -------------------------------------------------------------------------
  // Outstanding 计数器
  // 写：AW 握手 +1，B 握手 -1
  // 读：AR 握手 +1，R 握手 -1（R burst 每拍计一次，用 RLAST 时可改）
  // -------------------------------------------------------------------------
  logic [OUTSTANDING_W-1:0] wr_outstanding, rd_outstanding;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      wr_outstanding <= '0;
    else unique case ({aw_hshk, b_hshk})
      2'b10:   wr_outstanding <= wr_outstanding + 1;
      2'b01:   wr_outstanding <= wr_outstanding - 1;
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rd_outstanding <= '0;
    else unique case ({ar_hshk, r_hshk})
      2'b10:   rd_outstanding <= rd_outstanding + 1;
      2'b01:   rd_outstanding <= rd_outstanding - 1;
      default: ;
    endcase
  end

  // -------------------------------------------------------------------------
  // 条件检查
  // -------------------------------------------------------------------------
  logic [31:0] cond_subject;
  logic        trigger_valid;
  logic        cond_match;

  always_comb begin
    cond_subject  = '0;
    trigger_valid = 1'b0;
    unique case (cond_field)
      TRACE_FIELD_AW_ADDR: begin cond_subject = awaddr;          trigger_valid = aw_hshk;           end
      TRACE_FIELD_AR_ADDR: begin cond_subject = araddr;          trigger_valid = ar_hshk;           end
      TRACE_FIELD_W_DATA:  begin cond_subject = wdata;           trigger_valid = w_hshk;            end
      TRACE_FIELD_R_DATA:  begin cond_subject = rdata;           trigger_valid = r_hshk;            end
      TRACE_FIELD_AW_ID:   begin cond_subject = 32'(awid);       trigger_valid = aw_hshk;           end
      TRACE_FIELD_AR_ID:   begin cond_subject = 32'(arid);       trigger_valid = ar_hshk;           end
      TRACE_FIELD_BURST:   begin cond_subject = 32'(awburst);    trigger_valid = aw_hshk | ar_hshk; end
      default:             begin cond_subject = '0;              trigger_valid = 1'b0;              end
    endcase
  end

  always_comb begin
    unique case (cond_op)
      TRACE_OP_EQ:  cond_match = (cond_subject == cond_val);
      TRACE_OP_NEQ: cond_match = (cond_subject != cond_val);
      TRACE_OP_GT:  cond_match = (cond_subject >  cond_val);
      TRACE_OP_LT:  cond_match = (cond_subject <  cond_val);
      TRACE_OP_GTE: cond_match = (cond_subject >= cond_val);
      TRACE_OP_LTE: cond_match = (cond_subject <= cond_val);
      default:      cond_match = 1'b0;
    endcase
  end

  // -------------------------------------------------------------------------
  // 构建待写入 SRAM 的条目
  // -------------------------------------------------------------------------
  trace_entry_t wr_entry;

  always_comb begin
    wr_entry = '0;
    unique case (cond_field)
      TRACE_FIELD_AW_ADDR,
      TRACE_FIELD_AW_ID: begin
        wr_entry.addr        = awaddr;
        wr_entry.data        = '0;
        wr_entry.id          = awid;
        wr_entry.burst       = awburst;
        wr_entry.outstanding = wr_outstanding;
      end
      TRACE_FIELD_W_DATA: begin
        wr_entry.addr        = '0;
        wr_entry.data        = wdata;
        wr_entry.id          = '0;
        wr_entry.burst       = '0;
        wr_entry.outstanding = wr_outstanding;
      end
      TRACE_FIELD_AR_ADDR,
      TRACE_FIELD_AR_ID: begin
        wr_entry.addr        = araddr;
        wr_entry.data        = '0;
        wr_entry.id          = arid;
        wr_entry.burst       = arburst;
        wr_entry.outstanding = rd_outstanding;
      end
      TRACE_FIELD_R_DATA: begin
        wr_entry.addr        = '0;
        wr_entry.data        = rdata;
        wr_entry.id          = rid;
        wr_entry.burst       = '0;
        wr_entry.outstanding = rd_outstanding;
      end
      TRACE_FIELD_BURST: begin
        // AW 握手优先，AW/AR 同时时记录写通道
        wr_entry.addr        = aw_hshk ? awaddr  : araddr;
        wr_entry.data        = '0;
        wr_entry.id          = aw_hshk ? awid    : arid;
        wr_entry.burst       = aw_hshk ? awburst : arburst;
        wr_entry.outstanding = aw_hshk ? wr_outstanding : rd_outstanding;
      end
      default: wr_entry = '0;
    endcase
  end

  // -------------------------------------------------------------------------
  // SRAM 写使能：trace 使能 & 条件命中 & 非满
  // -------------------------------------------------------------------------
  logic sram_wen;
  assign sram_wen = trace_en & trigger_valid & cond_match & ~sram_full;

  // -------------------------------------------------------------------------
  // SRAM（触发器阵列，综合器推断为 RAM）
  // -------------------------------------------------------------------------
  trace_entry_t sram_mem [0:TRACE_DEPTH-1];

  logic [TRACE_PTR_W-1:0] wr_ptr, rd_ptr;
  logic [TRACE_PTR_W:0]   entry_cnt;

  assign sram_empty = (entry_cnt == '0);
  assign sram_full  = (entry_cnt == TRACE_PTR_W+1'(TRACE_DEPTH));
  assign sram_count = entry_cnt;

  // 写指针
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)       wr_ptr <= '0;
    else if (trace_clr) wr_ptr <= '0;
    else if (sram_wen)  wr_ptr <= wr_ptr + 1;
  end

  // 读指针（rd_req 脉冲时前移）
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)             rd_ptr <= '0;
    else if (trace_clr)     rd_ptr <= '0;
    else if (rd_req & ~sram_empty) rd_ptr <= rd_ptr + 1;
  end

  // 条目计数
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      entry_cnt <= '0;
    else if (trace_clr)
      entry_cnt <= '0;
    else unique case ({sram_wen, rd_req & ~sram_empty})
      2'b10:   entry_cnt <= entry_cnt + 1;
      2'b01:   entry_cnt <= entry_cnt - 1;
      default: ;
    endcase
  end

  // SRAM 写
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < TRACE_DEPTH; i++)
        sram_mem[i] <= '0;
    end else if (sram_wen)
      sram_mem[wr_ptr] <= wr_entry;
  end

  // -------------------------------------------------------------------------
  // 读出锁存器：rd_req 时将 sram_mem[rd_ptr] 锁存，rd_ptr 同拍后移
  // 软件可在之后任意时刻读取 rd_entry 寄存器
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rd_entry <= '0;
    else if (rd_req & ~sram_empty)
      rd_entry <= sram_mem[rd_ptr];
  end

endmodule
