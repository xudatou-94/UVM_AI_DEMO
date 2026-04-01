// =============================================================================
// axi_if.sv  AXI4 总线接口
// =============================================================================
interface axi_if #(
  parameter int ADDR_W = axi_pkg::AXI_ADDR_W,
  parameter int DATA_W = axi_pkg::AXI_DATA_W,
  parameter int ID_W   = axi_pkg::AXI_ID_W,
  parameter int STRB_W = DATA_W / 8
)(
  input logic aclk,
  input logic aresetn
);

  // ---- 写地址通道（master → slave）----
  logic [ID_W-1:0]   awid;
  logic [ADDR_W-1:0] awaddr;
  logic [7:0]        awlen;
  logic [2:0]        awsize;
  logic [1:0]        awburst;
  logic              awlock;
  logic [3:0]        awcache;
  logic [2:0]        awprot;
  logic [3:0]        awqos;
  logic              awvalid;
  logic              awready;

  // ---- 写数据通道（master → slave）----
  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wlast;
  logic              wvalid;
  logic              wready;

  // ---- 写响应通道（slave → master）----
  logic [ID_W-1:0]   bid;
  logic [1:0]        bresp;
  logic              bvalid;
  logic              bready;

  // ---- 读地址通道（master → slave）----
  logic [ID_W-1:0]   arid;
  logic [ADDR_W-1:0] araddr;
  logic [7:0]        arlen;
  logic [2:0]        arsize;
  logic [1:0]        arburst;
  logic              arlock;
  logic [3:0]        arcache;
  logic [2:0]        arprot;
  logic [3:0]        arqos;
  logic              arvalid;
  logic              arready;

  // ---- 读数据通道（slave → master）----
  logic [ID_W-1:0]   rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic              rlast;
  logic              rvalid;
  logic              rready;

  // ==========================================================================
  // Modport：master（驱动 AW/W/AR/BREADY/RREADY，监听其余）
  // ==========================================================================
  modport master_mp (
    input  aclk, aresetn,
    // AW
    output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
    input  awready,
    // W
    output wdata, wstrb, wlast, wvalid,
    input  wready,
    // B
    input  bid, bresp, bvalid,
    output bready,
    // AR
    output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
    input  arready,
    // R
    input  rid, rdata, rresp, rlast, rvalid,
    output rready
  );

  // ==========================================================================
  // Modport：slave（驱动 AWREADY/WREADY/ARREADY/B/R，监听其余）
  // ==========================================================================
  modport slave_mp (
    input  aclk, aresetn,
    // AW
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
    output awready,
    // W
    input  wdata, wstrb, wlast, wvalid,
    output wready,
    // B
    output bid, bresp, bvalid,
    input  bready,
    // AR
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
    output arready,
    // R
    output rid, rdata, rresp, rlast, rvalid,
    input  rready
  );

  // ==========================================================================
  // Modport：monitor（全部只读）
  // ==========================================================================
  modport monitor_mp (
    input aclk, aresetn,
    input awid, awaddr, awlen, awsize, awburst, awvalid, awready,
    input wdata, wstrb, wlast, wvalid, wready,
    input bid, bresp, bvalid, bready,
    input arid, araddr, arlen, arsize, arburst, arvalid, arready,
    input rid, rdata, rresp, rlast, rvalid, rready
  );

  // ==========================================================================
  // SVA：基本协议检查
  // ==========================================================================
  // AWVALID 一旦拉高不得无故撤销
  property p_awvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> awvalid;
  endproperty
  assert property (p_awvalid_stable)
    else $error("AXI: AWVALID deasserted without AWREADY");

  // ARVALID 同上
  property p_arvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> arvalid;
  endproperty
  assert property (p_arvalid_stable)
    else $error("AXI: ARVALID deasserted without ARREADY");

  // WVALID 同上
  property p_wvalid_stable;
    @(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> wvalid;
  endproperty
  assert property (p_wvalid_stable)
    else $error("AXI: WVALID deasserted without WREADY");

endinterface
