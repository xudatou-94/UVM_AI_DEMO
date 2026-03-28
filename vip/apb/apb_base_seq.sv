// =============================================================================
// apb_base_seq.sv - APB 基础 Sequence
//
// 提供 master 侧和 slave 侧的常用原子操作任务。
// Master sequence 继承本类后直接调用 write/read 任务；
// Slave sequence 继承后实现 respond 循环。
// =============================================================================

class apb_base_seq extends uvm_sequence #(apb_seq_item);
  `uvm_object_utils(apb_base_seq)

  function new(string name = "apb_base_seq");
    super.new(name);
  endfunction

  // -------------------------------------------------------------------------
  // Master 原子操作：写
  // -------------------------------------------------------------------------
  task write(logic [31:0] addr, logic [31:0] data,
             logic [2:0] pprot = 3'b000, logic [3:0] pstrb = 4'hF);
    apb_seq_item item;
    item = apb_seq_item::type_id::create("item");
    item.addr  = addr;
    item.rw    = 1;
    item.wdata = data;
    item.pprot = pprot;
    item.pstrb = pstrb;
    start_item(item);
    finish_item(item);
    if (item.pslverr)
      `uvm_warning("APB_SEQ", $sformatf("PSLVERR: WRITE addr=0x%08x", addr))
  endtask

  // -------------------------------------------------------------------------
  // Master 原子操作：读
  // -------------------------------------------------------------------------
  task read(logic [31:0] addr, output logic [31:0] rdata,
            input logic [2:0] pprot = 3'b000);
    apb_seq_item item;
    item = apb_seq_item::type_id::create("item");
    item.addr  = addr;
    item.rw    = 0;
    item.pprot = pprot;
    start_item(item);
    finish_item(item);
    rdata = item.rdata;
    if (item.pslverr)
      `uvm_warning("APB_SEQ", $sformatf("PSLVERR: READ addr=0x%08x", addr))
  endtask

  // -------------------------------------------------------------------------
  // Master 操作：读后核验（读回值与期望值比较）
  // -------------------------------------------------------------------------
  task read_check(logic [31:0] addr, logic [31:0] exp_data,
                  logic [31:0] mask = 32'hFFFF_FFFF);
    logic [31:0] rdata;
    read(addr, rdata);
    if ((rdata & mask) !== (exp_data & mask)) begin
      `uvm_error("APB_SEQ",
        $sformatf("READ_CHECK FAIL: addr=0x%08x exp=0x%08x got=0x%08x mask=0x%08x",
                  addr, exp_data, rdata, mask))
    end else begin
      `uvm_info("APB_SEQ",
        $sformatf("READ_CHECK PASS: addr=0x%08x data=0x%08x", addr, rdata), UVM_HIGH)
    end
  endtask

  virtual task body();
  endtask

endclass : apb_base_seq


// =============================================================================
// apb_slave_resp_seq.sv - APB Slave 响应 Sequence 基类
//
// Slave sequence 继承本类，通过重写 get_response 提供自定义响应逻辑。
// 默认实现：无限循环，读操作返回 0，写操作确认。
// =============================================================================
class apb_slave_resp_seq extends uvm_sequence #(apb_seq_item);
  `uvm_object_utils(apb_slave_resp_seq)

  // 简单内存模型（可由子类替换为真实存储）
  logic [31:0] mem [logic [31:0]];

  function new(string name = "apb_slave_resp_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item req, rsp;
    forever begin
      // 等待 slave driver 的请求
      p_sequencer.wait_for_sequences();
      if (p_sequencer.has_do_available()) begin
        `uvm_create(req)
        `uvm_rand_send(req)

        rsp = apb_seq_item::type_id::create("rsp");
        rsp.copy(req);

        // 响应逻辑：读返回内存值，写更新内存
        if (!req.rw) begin
          rsp.rdata = mem.exists(req.addr) ? mem[req.addr] : 32'hDEAD_BEEF;
        end else begin
          mem[req.addr] = req.wdata;
        end
        rsp.pslverr     = 0;
        rsp.wait_states = 0;
      end
    end
  endtask

endclass : apb_slave_resp_seq
