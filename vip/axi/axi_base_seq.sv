// =============================================================================
// axi_base_seq.sv  AXI4 基础 Sequence 集合
//
// 包含：
//   axi_base_seq         — 基类，提供写/读辅助方法
//   axi_write_seq        — 单次写事务
//   axi_read_seq         — 单次读事务
//   axi_burst_write_seq  — burst 写事务
//   axi_burst_read_seq   — burst 读事务
//   axi_rw_seq           — 先写后读（地址、数据可配置）
//
// slave 响应 sequence：
//   axi_slave_resp_seq   — 自动响应 OKAY，填充递增数据
// =============================================================================

// =============================================================================
// axi_base_seq
// =============================================================================
class axi_base_seq extends uvm_sequence #(axi_seq_item);
  `uvm_object_utils(axi_base_seq)

  import axi_pkg::*;

  function new(string name = "axi_base_seq");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------------
  // 辅助：发起一次写事务
  // ---------------------------------------------------------------------------
  task do_write(
    input  logic [31:0]  addr,
    input  logic [31:0]  data,
    input  logic [3:0]   strb     = 4'hF,
    input  logic [7:0]   id       = 8'h0,
    output axi_resp_e    resp
  );
    axi_seq_item item;
    `uvm_create(item)
    item.txn_type    = AXI_WRITE;
    item.awaddr      = addr;
    item.awid        = id;
    item.awlen       = 8'h0;      // 单拍
    item.awsize      = 3'h2;      // 4B
    item.awburst     = AXI_BURST_INCR;
    item.wdata       = new[1];
    item.wstrb       = new[1];
    item.wdata[0]    = data;
    item.wstrb[0]    = strb;
    // 默认无反压
    item.bready_bp_mode = AXI_BP_NONE;
    `uvm_send(item)
    resp = item.bresp;
  endtask

  // ---------------------------------------------------------------------------
  // 辅助：发起一次读事务
  // ---------------------------------------------------------------------------
  task do_read(
    input  logic [31:0]  addr,
    input  logic [7:0]   id       = 8'h0,
    output logic [31:0]  data,
    output axi_resp_e    resp
  );
    axi_seq_item item;
    `uvm_create(item)
    item.txn_type    = AXI_READ;
    item.araddr      = addr;
    item.arid        = id;
    item.arlen       = 8'h0;
    item.arsize      = 3'h2;
    item.arburst     = AXI_BURST_INCR;
    item.rready_bp_mode = AXI_BP_NONE;
    `uvm_send(item)
    data = item.rdata[0];
    resp = item.rresp[0];
  endtask

  // ---------------------------------------------------------------------------
  // 辅助：发起 burst 写事务
  // ---------------------------------------------------------------------------
  task do_burst_write(
    input  logic [31:0]  base_addr,
    input  logic [31:0]  wdata[],
    input  logic [7:0]   id        = 8'h0,
    output axi_resp_e    resp
  );
    axi_seq_item item;
    int unsigned  beats = wdata.size();
    `uvm_create(item)
    item.txn_type = AXI_WRITE;
    item.awaddr   = base_addr;
    item.awid     = id;
    item.awlen    = beats - 1;
    item.awsize   = 3'h2;
    item.awburst  = AXI_BURST_INCR;
    item.wdata    = new[beats];
    item.wstrb    = new[beats];
    foreach (wdata[i]) begin
      item.wdata[i] = wdata[i];
      item.wstrb[i] = 4'hF;
    end
    item.bready_bp_mode = AXI_BP_NONE;
    `uvm_send(item)
    resp = item.bresp;
  endtask

  // ---------------------------------------------------------------------------
  // 辅助：发起 burst 读事务
  // ---------------------------------------------------------------------------
  task do_burst_read(
    input  logic [31:0]  base_addr,
    input  logic [7:0]   beats,
    input  logic [7:0]   id        = 8'h0,
    output logic [31:0]  rdata[],
    output axi_resp_e    rresp[]
  );
    axi_seq_item item;
    `uvm_create(item)
    item.txn_type = AXI_READ;
    item.araddr   = base_addr;
    item.arid     = id;
    item.arlen    = beats - 1;
    item.arsize   = 3'h2;
    item.arburst  = AXI_BURST_INCR;
    item.rready_bp_mode = AXI_BP_NONE;
    `uvm_send(item)
    rdata = item.rdata;
    rresp = item.rresp;
  endtask

endclass

// =============================================================================
// axi_write_seq — 单次写（可配置地址/数据/反压）
// =============================================================================
class axi_write_seq extends axi_base_seq;
  `uvm_object_utils(axi_write_seq)

  import axi_pkg::*;

  rand logic [31:0]  addr  = 32'h0000_0000;
  rand logic [31:0]  data  = 32'h0;
  rand logic [3:0]   strb  = 4'hF;
  rand logic [7:0]   id    = 8'h0;

  // 反压配置（可在 test 中覆写）
  axi_bp_mode_e  bready_bp_mode  = AXI_BP_NONE;
  int unsigned   bready_bp_fixed = 0;
  int unsigned   bready_bp_min   = 0;
  int unsigned   bready_bp_max   = 4;

  axi_resp_e  resp;

  function new(string name = "axi_write_seq");
    super.new(name);
  endfunction

  task body();
    axi_seq_item item;
    `uvm_create(item)
    item.txn_type        = AXI_WRITE;
    item.awaddr          = addr;
    item.awid            = id;
    item.awlen           = 8'h0;
    item.awsize          = 3'h2;
    item.awburst         = AXI_BURST_INCR;
    item.wdata           = new[1]; item.wdata[0] = data;
    item.wstrb           = new[1]; item.wstrb[0] = strb;
    item.bready_bp_mode  = bready_bp_mode;
    item.bready_bp_fixed = bready_bp_fixed;
    item.bready_bp_min   = bready_bp_min;
    item.bready_bp_max   = bready_bp_max;
    `uvm_send(item)
    resp = item.bresp;
  endtask

endclass

// =============================================================================
// axi_read_seq — 单次读
// =============================================================================
class axi_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_read_seq)

  import axi_pkg::*;

  rand logic [31:0]  addr  = 32'h0000_0000;
  rand logic [7:0]   id    = 8'h0;

  axi_bp_mode_e  rready_bp_mode  = AXI_BP_NONE;
  int unsigned   rready_bp_fixed = 0;
  int unsigned   rready_bp_min   = 0;
  int unsigned   rready_bp_max   = 4;

  logic [31:0]  rdata;
  axi_resp_e    resp;

  function new(string name = "axi_read_seq");
    super.new(name);
  endfunction

  task body();
    axi_seq_item item;
    `uvm_create(item)
    item.txn_type         = AXI_READ;
    item.araddr           = addr;
    item.arid             = id;
    item.arlen            = 8'h0;
    item.arsize           = 3'h2;
    item.arburst          = AXI_BURST_INCR;
    item.rready_bp_mode   = rready_bp_mode;
    item.rready_bp_fixed  = rready_bp_fixed;
    item.rready_bp_min    = rready_bp_min;
    item.rready_bp_max    = rready_bp_max;
    `uvm_send(item)
    rdata = item.rdata[0];
    resp  = item.rresp[0];
  endtask

endclass

// =============================================================================
// axi_rw_seq — 先写后读，自动比较
// =============================================================================
class axi_rw_seq extends axi_base_seq;
  `uvm_object_utils(axi_rw_seq)

  import axi_pkg::*;

  rand logic [31:0]  addr = 32'h0000_0000;
  rand logic [31:0]  data = 32'h0;
  rand logic [7:0]   id   = 8'h0;

  function new(string name = "axi_rw_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0]  rd_data;
    axi_resp_e    wr_resp, rd_resp;

    do_write(addr, data, 4'hF, id, wr_resp);
    if (wr_resp != AXI_RESP_OKAY)
      `uvm_error("AXI_RW", $sformatf("Write FAILED: addr=%0h resp=%s", addr, wr_resp.name()))

    do_read(addr, id, rd_data, rd_resp);
    if (rd_resp != AXI_RESP_OKAY)
      `uvm_error("AXI_RW", $sformatf("Read FAILED: addr=%0h resp=%s", addr, rd_resp.name()))

    if (rd_data !== data)
      `uvm_error("AXI_RW",
        $sformatf("Data mismatch: addr=%0h exp=%0h got=%0h", addr, data, rd_data))
    else
      `uvm_info("AXI_RW",
        $sformatf("PASS: addr=%0h data=%0h", addr, data), UVM_MEDIUM)
  endtask

endclass

// =============================================================================
// axi_slave_resp_seq — Slave 响应序列（自动回 OKAY，填充递增伪数据）
// =============================================================================
class axi_slave_resp_seq extends uvm_sequence #(axi_seq_item);
  `uvm_object_utils(axi_slave_resp_seq)

  import axi_pkg::*;

  int unsigned  n_resp = 0;   // 0 = 无限响应

  function new(string name = "axi_slave_resp_seq");
    super.new(name);
  endfunction

  task body();
    int cnt = 0;
    forever begin
      axi_seq_item item;
      `uvm_create(item)
      // 无需填充 req 信息，driver 读 s_rdata / s_rresp / s_bresp
      item.s_bresp = AXI_RESP_OKAY;
      // 填充伪读数据（实际项目应由 memory model 填充）
      item.s_rdata = new[8];
      item.s_rresp = AXI_RESP_OKAY;
      for (int i = 0; i < 8; i++)
        item.s_rdata[i] = $urandom();
      `uvm_send(item)
      cnt++;
      if (n_resp > 0 && cnt >= n_resp) break;
    end
  endtask

endclass
