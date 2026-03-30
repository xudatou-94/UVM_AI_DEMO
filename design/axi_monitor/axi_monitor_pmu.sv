// =============================================================================
// axi_monitor_pmu.sv
// PMU 组件：周期性统计 AXI 各通道握手次数，周期结束时快照到寄存器
//
// 统计通道：AW / W / B / AR / R
// 周期由 pmu_period 配置（单位：时钟周期）
// period_done 时将当前周期累计值锁存到 snap_* 寄存器，计数器归零重新开始
// =============================================================================
module axi_monitor_pmu
  import axi_monitor_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  // 配置
  input  logic        pmu_en,       // PMU 使能
  input  logic [31:0] pmu_period,   // 统计周期长度（时钟数）

  // AXI 通道握手输入
  input  logic aw_hshk,   // AWVALID & AWREADY
  input  logic w_hshk,    // WVALID  & WREADY
  input  logic b_hshk,    // BVALID  & BREADY
  input  logic ar_hshk,   // ARVALID & ARREADY
  input  logic r_hshk,    // RVALID  & RREADY

  // 快照寄存器输出（周期结束时更新）
  output logic [PMU_CNT_W-1:0] snap_aw_cnt,
  output logic [PMU_CNT_W-1:0] snap_w_cnt,
  output logic [PMU_CNT_W-1:0] snap_b_cnt,
  output logic [PMU_CNT_W-1:0] snap_ar_cnt,
  output logic [PMU_CNT_W-1:0] snap_r_cnt
);

  // -------------------------------------------------------------------------
  // 周期计数器
  // -------------------------------------------------------------------------
  logic [31:0] period_cnt;
  logic        period_done;

  assign period_done = pmu_en && (pmu_period != '0) && (period_cnt == pmu_period - 1);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      period_cnt <= '0;
    else if (!pmu_en)
      period_cnt <= '0;
    else if (period_done)
      period_cnt <= '0;
    else
      period_cnt <= period_cnt + 1;
  end

  // -------------------------------------------------------------------------
  // 各通道计数器
  // period_done 时同步清零（快照在同一拍完成，见下方）
  // -------------------------------------------------------------------------
  logic [PMU_CNT_W-1:0] cnt_aw, cnt_w, cnt_b, cnt_ar, cnt_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_aw <= '0; cnt_w  <= '0; cnt_b  <= '0;
      cnt_ar <= '0; cnt_r  <= '0;
    end else if (!pmu_en || period_done) begin
      cnt_aw <= '0; cnt_w  <= '0; cnt_b  <= '0;
      cnt_ar <= '0; cnt_r  <= '0;
    end else begin
      if (aw_hshk) cnt_aw <= cnt_aw + 1;
      if (w_hshk)  cnt_w  <= cnt_w  + 1;
      if (b_hshk)  cnt_b  <= cnt_b  + 1;
      if (ar_hshk) cnt_ar <= cnt_ar + 1;
      if (r_hshk)  cnt_r  <= cnt_r  + 1;
    end
  end

  // -------------------------------------------------------------------------
  // 快照寄存器：period_done 时将本周期最终值（含当拍握手）锁存
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      snap_aw_cnt <= '0; snap_w_cnt  <= '0; snap_b_cnt  <= '0;
      snap_ar_cnt <= '0; snap_r_cnt  <= '0;
    end else if (period_done) begin
      snap_aw_cnt <= cnt_aw + PMU_CNT_W'(aw_hshk);
      snap_w_cnt  <= cnt_w  + PMU_CNT_W'(w_hshk);
      snap_b_cnt  <= cnt_b  + PMU_CNT_W'(b_hshk);
      snap_ar_cnt <= cnt_ar + PMU_CNT_W'(ar_hshk);
      snap_r_cnt  <= cnt_r  + PMU_CNT_W'(r_hshk);
    end
  end

endmodule
