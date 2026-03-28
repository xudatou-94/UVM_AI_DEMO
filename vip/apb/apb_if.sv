// =============================================================================
// apb_if.sv - APB 接口定义
//
// 遵循 AMBA APB 协议规范（APB3/APB4）：
//   PCLK    - APB 时钟
//   PRESETn - 异步复位，低有效
//   PADDR   - 地址总线（参数化宽度，默认 32bit）
//   PSEL    - 片选信号
//   PENABLE - 使能信号（APB 二阶段握手）
//   PWRITE  - 读写方向：1=写，0=读
//   PWDATA  - 写数据总线（参数化宽度，默认 32bit）
//   PRDATA  - 读数据总线
//   PREADY  - 从设备就绪（APB3 扩展）
//   PSLVERR - 从设备错误（APB3 扩展）
//
// modport 说明：
//   master_mp  - master driver 使用（驱动除 PRDATA/PREADY/PSLVERR 外所有信号）
//   slave_mp   - slave driver 使用（驱动 PRDATA/PREADY/PSLVERR）
//   monitor_mp - monitor 使用（只读所有信号）
// =============================================================================

interface apb_if #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32
) (
  input logic PCLK,
  input logic PRESETn
);

  // -------------------------------------------------------------------------
  // APB 总线信号
  // -------------------------------------------------------------------------
  logic [ADDR_W-1:0] PADDR;
  logic              PSEL;
  logic              PENABLE;
  logic              PWRITE;
  logic [DATA_W-1:0] PWDATA;
  logic [DATA_W-1:0] PRDATA;
  logic              PREADY;
  logic              PSLVERR;

  // APB4 扩展（可选，默认不使用）
  logic [2:0]        PPROT;      // 保护属性
  logic [DATA_W/8-1:0] PSTRB;   // 写字节使能

  // -------------------------------------------------------------------------
  // modport：master
  // -------------------------------------------------------------------------
  modport master_mp (
    input  PCLK,
    input  PRESETn,
    output PADDR,
    output PSEL,
    output PENABLE,
    output PWRITE,
    output PWDATA,
    output PPROT,
    output PSTRB,
    input  PRDATA,
    input  PREADY,
    input  PSLVERR
  );

  // -------------------------------------------------------------------------
  // modport：slave
  // -------------------------------------------------------------------------
  modport slave_mp (
    input  PCLK,
    input  PRESETn,
    input  PADDR,
    input  PSEL,
    input  PENABLE,
    input  PWRITE,
    input  PWDATA,
    input  PPROT,
    input  PSTRB,
    output PRDATA,
    output PREADY,
    output PSLVERR
  );

  // -------------------------------------------------------------------------
  // modport：monitor（只读）
  // -------------------------------------------------------------------------
  modport monitor_mp (
    input  PCLK,
    input  PRESETn,
    input  PADDR,
    input  PSEL,
    input  PENABLE,
    input  PWRITE,
    input  PWDATA,
    input  PPROT,
    input  PSTRB,
    input  PRDATA,
    input  PREADY,
    input  PSLVERR
  );

  // -------------------------------------------------------------------------
  // 断言：APB 协议检查（仿真时自动激活）
  // -------------------------------------------------------------------------
`ifndef SYNTHESIS
  // SETUP 阶段：PENABLE 必须为 0
  property p_setup_penable;
    @(posedge PCLK) disable iff (!PRESETn)
    $rose(PSEL) |-> !PENABLE;
  endproperty

  // ACCESS 阶段：PENABLE 跟随 PSEL 后一拍
  property p_access_penable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> (PSEL && PENABLE);
  endproperty

  // PADDR/PWRITE/PWDATA 在整个事务期间保持稳定
  property p_addr_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && !PREADY) |=> $stable(PADDR);
  endproperty

  assert property (p_setup_penable)
    else `uvm_error("APB_IF", "APB 违例：SETUP 阶段 PENABLE 不为 0")
  assert property (p_access_penable)
    else `uvm_error("APB_IF", "APB 违例：ACCESS 阶段 PENABLE 未拉高")
  assert property (p_addr_stable)
    else `uvm_error("APB_IF", "APB 违例：事务期间 PADDR 发生变化")
`endif

endinterface : apb_if
