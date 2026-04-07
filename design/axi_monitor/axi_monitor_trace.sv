// =============================================================================
// axi_monitor_trace.sv
// Trace 组件：工作在 trace_clk 域，接收来自 axi_ch_cdc 的已同步事件
//
// outstanding 计数在 trace_clk 域由同步后的 aw/b/ar/r 事件重新推导，
// 避免多比特跨时钟同步问题。
// =============================================================================
module axi_monitor_trace
  import axi_monitor_pkg::*;
(
  input  logic trace_clk,
  input  logic rst_n,

  // 配置（来自寄存器文件，已同步或同域）
  input  logic         trace_en,
  input  logic         trace_clr,
  input  trace_field_e cond_field,
  input  trace_op_e    cond_op,
  input  logic [31:0]  cond_val,

  // 选中通道的同步事件（trace_clk 域）
  input  axi_ch_events_t events,

  // SRAM 状态输出
  output logic                   sram_empty,
  output logic [TRACE_PTR_W:0]   sram_count,
  output logic                   sram_full,

  // 软件读出接口
  input  logic         rd_req,
  output trace_entry_t rd_entry
);

  // =========================================================================
  // outstanding 计数器（在 trace_clk 域从同步事件重新推导）
  // =========================================================================
  logic [OUTSTANDING_W-1:0] wr_outstanding, rd_outstanding;

  always_ff @(posedge trace_clk or negedge rst_n) begin
    if (!rst_n)
      wr_outstanding <= '0;
    else unique case ({events.aw_event, events.b_event})
      2'b10:   wr_outstanding <= wr_outstanding + 1;
      2'b01:   wr_outstanding <= wr_outstanding - 1;
      default: ;
    endcase
  end

  always_ff @(posedge trace_clk or negedge rst_n) begin
    if (!rst_n)
      rd_outstanding <= '0;
    else unique case ({events.ar_event, events.r_event})
      2'b10:   rd_outstanding <= rd_outstanding + 1;
      2'b01:   rd_outstanding <= rd_outstanding - 1;
      default: ;
    endcase
  end

  // =========================================================================
  // 条件检查
  // =========================================================================
  logic [31:0] cond_subject;
  logic        trigger_valid;
  logic        cond_match;

  always_comb begin
    cond_subject  = '0;
    trigger_valid = 1'b0;
    unique case (cond_field)
      TRACE_FIELD_AW_ADDR: begin cond_subject = events.aw_addr;      trigger_valid = events.aw_event;                    end
      TRACE_FIELD_AR_ADDR: begin cond_subject = events.ar_addr;      trigger_valid = events.ar_event;                    end
      TRACE_FIELD_W_DATA:  begin cond_subject = events.w_data;       trigger_valid = events.w_event;                     end
      TRACE_FIELD_R_DATA:  begin cond_subject = events.r_data;       trigger_valid = events.r_event;                     end
      TRACE_FIELD_AW_ID:   begin cond_subject = 32'(events.aw_id);   trigger_valid = events.aw_event;                    end
      TRACE_FIELD_AR_ID:   begin cond_subject = 32'(events.ar_id);   trigger_valid = events.ar_event;                    end
      TRACE_FIELD_BURST:   begin cond_subject = 32'(events.aw_burst);trigger_valid = events.aw_event | events.ar_event;  end
      default:             begin cond_subject = '0;                  trigger_valid = 1'b0;                               end
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

  // =========================================================================
  // 构建待写入条目
  // =========================================================================
  trace_entry_t wr_entry;

  always_comb begin
    wr_entry = '0;
    unique case (cond_field)
      TRACE_FIELD_AW_ADDR,
      TRACE_FIELD_AW_ID: begin
        wr_entry.addr        = events.aw_addr;
        wr_entry.data        = '0;
        wr_entry.id          = events.aw_id;
        wr_entry.burst       = events.aw_burst;
        wr_entry.outstanding = wr_outstanding;
      end
      TRACE_FIELD_W_DATA: begin
        wr_entry.addr        = '0;
        wr_entry.data        = events.w_data;
        wr_entry.id          = '0;
        wr_entry.burst       = '0;
        wr_entry.outstanding = wr_outstanding;
      end
      TRACE_FIELD_AR_ADDR,
      TRACE_FIELD_AR_ID: begin
        wr_entry.addr        = events.ar_addr;
        wr_entry.data        = '0;
        wr_entry.id          = events.ar_id;
        wr_entry.burst       = events.ar_burst;
        wr_entry.outstanding = rd_outstanding;
      end
      TRACE_FIELD_R_DATA: begin
        wr_entry.addr        = '0;
        wr_entry.data        = events.r_data;
        wr_entry.id          = events.r_id;
        wr_entry.burst       = '0;
        wr_entry.outstanding = rd_outstanding;
      end
      TRACE_FIELD_BURST: begin
        // AW/AR 同时触发时优先记录写通道
        wr_entry.addr        = events.aw_event ? events.aw_addr  : events.ar_addr;
        wr_entry.data        = '0;
        wr_entry.id          = events.aw_event ? events.aw_id    : events.ar_id;
        wr_entry.burst       = events.aw_event ? events.aw_burst : events.ar_burst;
        wr_entry.outstanding = events.aw_event ? wr_outstanding  : rd_outstanding;
      end
      default: wr_entry = '0;
    endcase
  end

  // =========================================================================
  // SRAM 写使能
  // =========================================================================
  logic sram_wen;
  assign sram_wen = trace_en & trigger_valid & cond_match & ~sram_full;

  // =========================================================================
  // SRAM（触发器阵列）
  // =========================================================================
  trace_entry_t sram_mem [0:TRACE_DEPTH-1];

  logic [TRACE_PTR_W-1:0] wr_ptr, rd_ptr;
  logic [TRACE_PTR_W:0]   entry_cnt;

  assign sram_empty = (entry_cnt == '0);
  assign sram_full  = (entry_cnt == TRACE_PTR_W+1'(TRACE_DEPTH));
  assign sram_count = entry_cnt;

  always_ff @(posedge trace_clk or negedge rst_n) begin
    if (!rst_n)        wr_ptr <= '0;
    else if (trace_clr)wr_ptr <= '0;
    else if (sram_wen) wr_ptr <= wr_ptr + 1;
  end

  always_ff @(posedge trace_clk or negedge rst_n) begin
    if (!rst_n)                    rd_ptr <= '0;
    else if (trace_clr)            rd_ptr <= '0;
    else if (rd_req & ~sram_empty) rd_ptr <= rd_ptr + 1;
  end

  always_ff @(posedge trace_clk or negedge rst_n) begin
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

  always_ff @(posedge trace_clk or negedge rst_n) begin
    if (!rst_n)
      for (int i = 0; i < TRACE_DEPTH; i++) sram_mem[i] <= '0;
    else if (sram_wen)
      sram_mem[wr_ptr] <= wr_entry;
  end

  // =========================================================================
  // 读出锁存器：rd_req 时将 sram_mem[rd_ptr] 锁存，rd_ptr 同拍后移
  // =========================================================================
  always_ff @(posedge trace_clk or negedge rst_n) begin
    if (!rst_n)
      rd_entry <= '0;
    else if (rd_req & ~sram_empty)
      rd_entry <= sram_mem[rd_ptr];
  end

endmodule
