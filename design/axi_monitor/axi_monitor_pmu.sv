// =============================================================================
// axi_monitor_pmu.sv
// PMU 组件：周期性统计 AXI 各通道握手次数及响应错误次数
//
// 统计通道：AW / W / B / AR / R
// 错误统计：BRESP[1]=1（SLVERR/DECERR）/ RRESP[1]=1
// 周期结束时将当前计数（含当拍握手）锁存到快照寄存器，计数器归零
// =============================================================================
module axi_monitor_pmu
  import axi_monitor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  // 配置
  input  logic        pmu_en,
  input  logic [31:0] pmu_period,

  // AXI 通道握手输入
  input  logic aw_hshk,
  input  logic w_hshk,
  input  logic b_hshk,
  input  logic ar_hshk,
  input  logic r_hshk,

  // 响应数据（用于错误检测）
  input  logic [1:0] bresp,   // BRESP，bit[1]=1 表示错误
  input  logic [1:0] rresp,   // RRESP，bit[1]=1 表示错误

  // 快照寄存器输出
  output logic [PMU_CNT_W-1:0] snap_aw_cnt,
  output logic [PMU_CNT_W-1:0] snap_w_cnt,
  output logic [PMU_CNT_W-1:0] snap_b_cnt,
  output logic [PMU_CNT_W-1:0] snap_ar_cnt,
  output logic [PMU_CNT_W-1:0] snap_r_cnt,
  output logic [PMU_CNT_W-1:0] snap_b_err_cnt,  // BRESP 错误快照
  output logic [PMU_CNT_W-1:0] snap_r_err_cnt   // RRESP 错误快照
);

  // -------------------------------------------------------------------------
  // 错误握手
  // -------------------------------------------------------------------------
  logic b_err_hshk, r_err_hshk;
  assign b_err_hshk = b_hshk & bresp[1];
  assign r_err_hshk = r_hshk & rresp[1];

  // -------------------------------------------------------------------------
  // 周期计数器
  // -------------------------------------------------------------------------
  logic [31:0] period_cnt;
  logic        period_done;

  assign period_done = pmu_en && (pmu_period != '0) && (period_cnt == pmu_period - 1);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)          period_cnt <= '0;
    else if (!pmu_en)    period_cnt <= '0;
    else if (period_done)period_cnt <= '0;
    else                 period_cnt <= period_cnt + 1;
  end

  // -------------------------------------------------------------------------
  // 通道计数器
  // -------------------------------------------------------------------------
  logic [PMU_CNT_W-1:0] cnt_aw, cnt_w, cnt_b, cnt_ar, cnt_r;
  logic [PMU_CNT_W-1:0] cnt_b_err, cnt_r_err;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_aw <= '0; cnt_w  <= '0; cnt_b    <= '0;
      cnt_ar <= '0; cnt_r  <= '0;
      cnt_b_err <= '0; cnt_r_err <= '0;
    end else if (!pmu_en || period_done) begin
      cnt_aw <= '0; cnt_w  <= '0; cnt_b    <= '0;
      cnt_ar <= '0; cnt_r  <= '0;
      cnt_b_err <= '0; cnt_r_err <= '0;
    end else begin
      if (aw_hshk)    cnt_aw    <= cnt_aw    + 1;
      if (w_hshk)     cnt_w     <= cnt_w     + 1;
      if (b_hshk)     cnt_b     <= cnt_b     + 1;
      if (ar_hshk)    cnt_ar    <= cnt_ar    + 1;
      if (r_hshk)     cnt_r     <= cnt_r     + 1;
      if (b_err_hshk) cnt_b_err <= cnt_b_err + 1;
      if (r_err_hshk) cnt_r_err <= cnt_r_err + 1;
    end
  end

  // -------------------------------------------------------------------------
  // 快照寄存器：period_done 时锁存（含当拍）
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      snap_aw_cnt    <= '0; snap_w_cnt     <= '0; snap_b_cnt <= '0;
      snap_ar_cnt    <= '0; snap_r_cnt     <= '0;
      snap_b_err_cnt <= '0; snap_r_err_cnt <= '0;
    end else if (period_done) begin
      snap_aw_cnt    <= cnt_aw    + PMU_CNT_W'(aw_hshk);
      snap_w_cnt     <= cnt_w     + PMU_CNT_W'(w_hshk);
      snap_b_cnt     <= cnt_b     + PMU_CNT_W'(b_hshk);
      snap_ar_cnt    <= cnt_ar    + PMU_CNT_W'(ar_hshk);
      snap_r_cnt     <= cnt_r     + PMU_CNT_W'(r_hshk);
      snap_b_err_cnt <= cnt_b_err + PMU_CNT_W'(b_err_hshk);
      snap_r_err_cnt <= cnt_r_err + PMU_CNT_W'(r_err_hshk);
    end
  end

endmodule
