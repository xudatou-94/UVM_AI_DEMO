// =============================================================================
// tb_top.sv - sjtag2apb 验证顶层模块
//
// 职责：
//   1. 产生 TCK 和 PCLK 两个时钟域（频率可通过 plusarg 配置）
//   2. 产生复位序列（PCLK 域和 TCK 域分别复位）
//   3. 实例化 DUT（sjtag2apb_bridge）
//   4. 实例化 SJTAG/APB 接口并连接到 DUT
//   5. 通过 uvm_config_db 将接口传递给 UVM 组件
//   6. 启动 UVM 仿真（run_test）
//   7. 超时看门狗（防止仿真卡死）
//
// 时钟 plusarg：
//   +TCK_HALF_NS=N     TCK 半周期（ns），默认 50（10MHz）
//   +PCLK_HALF_NS=N    PCLK 半周期（ns），默认 5（100MHz）
//   +CASE_TIMEOUT=N    仿真超时（秒），默认 1800
// =============================================================================

`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import sjtag_pkg::*;
  import apb_pkg::*;
  import sjtag2apb_tb_pkg::*;
  import sjtag2apb_pkg::*;

  // --------------------------------------------------------------------------
  // 时钟参数（可被 plusarg 覆盖）
  // --------------------------------------------------------------------------
  int unsigned tck_half_ns  = 50;   // TCK 半周期，默认 50ns（10MHz）
  int unsigned pclk_half_ns = 5;    // PCLK 半周期，默认 5ns（100MHz）

  // --------------------------------------------------------------------------
  // 时钟信号
  // --------------------------------------------------------------------------
  logic tck  = 1'b0;
  logic pclk = 1'b0;

  // --------------------------------------------------------------------------
  // 复位信号
  // --------------------------------------------------------------------------
  logic trst_n  = 1'b0;
  logic presetn = 1'b0;

  // --------------------------------------------------------------------------
  // 接口实例化
  // --------------------------------------------------------------------------
  sjtag_if sjtag_if_inst ();
  apb_if   apb_if_inst   (.PCLK(pclk), .PRESETn(presetn));

  // --------------------------------------------------------------------------
  // 时钟生成（由 tck_half_ns / pclk_half_ns 控制，支持运行时修改频率）
  // --------------------------------------------------------------------------
  always #(tck_half_ns  * 1ns) tck  = ~tck;
  always #(pclk_half_ns * 1ns) pclk = ~pclk;

  // --------------------------------------------------------------------------
  // 将时钟和复位连接到 SJTAG 接口
  // --------------------------------------------------------------------------
  assign sjtag_if_inst.tck    = tck;
  assign sjtag_if_inst.trst_n = trst_n;

  // --------------------------------------------------------------------------
  // DUT 实例化
  // --------------------------------------------------------------------------
  sjtag2apb_bridge dut (
    // JTAG 端口
    .tck      (sjtag_if_inst.tck),
    .trst_n   (sjtag_if_inst.trst_n),
    .tms      (sjtag_if_inst.tms),
    .tdi      (sjtag_if_inst.tdi),
    .tdo      (sjtag_if_inst.tdo),
    // APB 端口
    .pclk     (pclk),
    .presetn  (presetn),
    .psel     (apb_if_inst.PSEL),
    .penable  (apb_if_inst.PENABLE),
    .pwrite   (apb_if_inst.PWRITE),
    .paddr    (apb_if_inst.PADDR),
    .pwdata   (apb_if_inst.PWDATA),
    .prdata   (apb_if_inst.PRDATA),
    .pready   (apb_if_inst.PREADY),
    .pslverr  (apb_if_inst.PSLVERR)
  );

  // --------------------------------------------------------------------------
  // 初始化 & UVM 启动
  // --------------------------------------------------------------------------
  initial begin
    int unsigned timeout_s;

    // 读取时钟和超时配置
    void'($value$plusargs("TCK_HALF_NS=%0d",  tck_half_ns));
    void'($value$plusargs("PCLK_HALF_NS=%0d", pclk_half_ns));
    timeout_s = 1800;
    void'($value$plusargs("CASE_TIMEOUT=%0d", timeout_s));

    // ---- 复位序列 ----
    // 先拉低两路复位
    trst_n  = 1'b0;
    presetn = 1'b0;

    // PCLK 域：等待 10 个 PCLK 后释放 PRESETn
    repeat(10) @(posedge pclk);
    presetn = 1'b1;

    // TCK 域：再等待 5 个 TCK 后释放 TRST_N
    repeat(5) @(posedge tck);
    trst_n = 1'b1;
    @(posedge tck);

    // ---- 将接口传递给 UVM config_db ----
    // SJTAG VIP driver/monitor 使用 "vif" key
    uvm_config_db #(virtual sjtag_if)::set(null, "uvm_test_top.*", "vif", sjtag_if_inst);
    // APB VIP monitor 使用 "vif" key
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.*", "vif", apb_if_inst);
    // APB slave model 使用 "apb_vif" key
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.*", "apb_vif", apb_if_inst);

    // 将 TCK 半周期传递给 env（env 再传给 SJTAG agent cfg）
    uvm_config_db #(int unsigned)::set(null, "uvm_test_top", "tck_half_period_ns", tck_half_ns);

    // ---- 超时看门狗 fork ----
    fork
      begin
        // 在独立 fork 中等待超时，超时则终止仿真
        #(timeout_s * 1s);
        `uvm_fatal("TIMEOUT",
          $sformatf("仿真超时：已运行 %0d 秒，请检查是否存在死锁", timeout_s))
      end
    join_none

    // ---- 启动 UVM 仿真 ----
    run_test();
  end

endmodule : tb_top
