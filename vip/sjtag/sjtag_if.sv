// =============================================================================
// sjtag_if.sv - SJTAG 接口定义
//
// 信号说明：
//   tck    - JTAG 时钟，由 VIP driver 主动生成
//   trst_n - 异步复位，低有效
//   tms    - 测试模式选择
//   tdi    - 测试数据输入（主机→DUT）
//   tdo    - 测试数据输出（DUT→主机）
//
// 注：TCK 由 driver 内部生成，不使用 clocking block 驱动，
//     monitor 通过 @(posedge tck) 事件采样。
// =============================================================================

interface sjtag_if;
  logic tck;
  logic trst_n;
  logic tms;
  logic tdi;
  logic tdo;

  // -------------------------------------------------------------------------
  // modport：master（driver 使用）
  // -------------------------------------------------------------------------
  modport master_mp (
    output tck,
    output trst_n,
    output tms,
    output tdi,
    input  tdo
  );

  // -------------------------------------------------------------------------
  // modport：monitor（只读）
  // -------------------------------------------------------------------------
  modport monitor_mp (
    input  tck,
    input  trst_n,
    input  tms,
    input  tdi,
    input  tdo
  );

endinterface : sjtag_if
