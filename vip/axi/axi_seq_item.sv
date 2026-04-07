// =============================================================================
// axi_seq_item.sv  AXI4 事务描述符
//
// 统一 seq_item，master 和 slave 均使用，通过 txn_type 区分读/写。
//
// 反压字段说明（master 侧）：
//   bready_bp_*  - 写响应通道，master 控制 BREADY 延迟
//   rready_bp_*  - 读数据通道，master 控制 RREADY 延迟（对每个 beat 独立生效）
//
// 反压字段说明（slave 侧）：
//   wready_bp_*  - 写数据通道，slave 控制 WREADY 延迟（对每个 beat 独立生效）
//   awready/arready 延迟通过 axi_agent_cfg 全局配置（详见设计文档）
// =============================================================================
class axi_seq_item extends uvm_sequence_item;
  `uvm_object_utils_begin(axi_seq_item)
    `uvm_field_enum  (axi_pkg::axi_txn_type_e, txn_type,  UVM_ALL_ON)
    `uvm_field_int   (awid,    UVM_ALL_ON)
    `uvm_field_int   (awaddr,  UVM_ALL_ON)
    `uvm_field_int   (awlen,   UVM_ALL_ON)
    `uvm_field_int   (awsize,  UVM_ALL_ON)
    `uvm_field_enum  (axi_pkg::axi_burst_e, awburst, UVM_ALL_ON)
    `uvm_field_array_int(wdata, UVM_ALL_ON)
    `uvm_field_array_int(wstrb, UVM_ALL_ON)
    `uvm_field_enum  (axi_pkg::axi_resp_e,  bresp,   UVM_ALL_ON)
    `uvm_field_int   (arid,    UVM_ALL_ON)
    `uvm_field_int   (araddr,  UVM_ALL_ON)
    `uvm_field_int   (arlen,   UVM_ALL_ON)
    `uvm_field_int   (arsize,  UVM_ALL_ON)
    `uvm_field_enum  (axi_pkg::axi_burst_e, arburst, UVM_ALL_ON)
    `uvm_field_array_int(rdata, UVM_ALL_ON)
    `uvm_field_array_enum(axi_pkg::axi_resp_e, rresp, UVM_ALL_ON)
  `uvm_object_utils_end

  import axi_pkg::*;

  // ---- 写地址 ----
  rand axi_txn_type_e             txn_type;
  rand logic [AXI_ADDR_W-1:0]    awaddr;
  rand logic [AXI_ID_W-1:0]      awid;
  rand logic [7:0]                awlen;
  rand logic [2:0]                awsize;
  rand axi_burst_e                awburst;

  // ---- 写数据（burst 数组）----
  rand logic [AXI_DATA_W-1:0]    wdata[];
  rand logic [AXI_STRB_W-1:0]    wstrb[];

  // ---- 写响应（driver 填充）----
       axi_resp_e                 bresp;

  // ---- 读地址 ----
  rand logic [AXI_ADDR_W-1:0]    araddr;
  rand logic [AXI_ID_W-1:0]      arid;
  rand logic [7:0]                arlen;
  rand logic [2:0]                arsize;
  rand axi_burst_e                arburst;

  // ---- 读数据（driver 填充）----
       logic [AXI_DATA_W-1:0]    rdata[];
       axi_resp_e                 rresp[];

  // ---- slave 响应数据（slave response seq 填充）----
       logic [AXI_DATA_W-1:0]    s_rdata[];   // slave 提供的读数据
       axi_resp_e                 s_rresp;     // per-burst resp
       axi_resp_e                 s_bresp;     // 写响应

  // ==========================================================================
  // 反压配置（master 侧）
  // ==========================================================================
  // BREADY：每笔写事务触发一次延迟后拉高 BREADY
  rand axi_bp_mode_e  bready_bp_mode;
  rand int unsigned   bready_bp_fixed;
  rand int unsigned   bready_bp_min;
  rand int unsigned   bready_bp_max;

  // RREADY：每个 R beat 触发一次延迟后拉高 RREADY
  rand axi_bp_mode_e  rready_bp_mode;
  rand int unsigned   rready_bp_fixed;
  rand int unsigned   rready_bp_min;
  rand int unsigned   rready_bp_max;

  // ==========================================================================
  // 反压配置（slave 侧）
  // ==========================================================================
  // WREADY：每个 W beat 触发一次延迟后拉高 WREADY
  rand axi_bp_mode_e  wready_bp_mode;
  rand int unsigned   wready_bp_fixed;
  rand int unsigned   wready_bp_min;
  rand int unsigned   wready_bp_max;

  // ==========================================================================
  // 约束
  // ==========================================================================
  constraint c_burst_default {
    soft awburst == AXI_BURST_INCR;
    soft arburst == AXI_BURST_INCR;
    soft awlen   == 8'h0;   // 默认单拍
    soft arlen   == 8'h0;
    soft awsize  == 3'h2;   // 默认 4B
    soft arsize  == 3'h2;
    awaddr[1:0] == 2'b00;   // 4B 对齐
    araddr[1:0] == 2'b00;
  }

  constraint c_wdata_size {
    wdata.size() == awlen + 1;
    wstrb.size() == awlen + 1;
  }

  // 默认无反压
  constraint c_bp_default {
    soft bready_bp_mode  == AXI_BP_NONE;
    soft rready_bp_mode  == AXI_BP_NONE;
    soft wready_bp_mode  == AXI_BP_NONE;
  }

  constraint c_bp_range {
    bready_bp_min <= bready_bp_max; bready_bp_max <= 16;
    rready_bp_min <= rready_bp_max; rready_bp_max <= 16;
    wready_bp_min <= wready_bp_max; wready_bp_max <= 16;
  }

  function new(string name = "axi_seq_item");
    super.new(name);
  endfunction

endclass
