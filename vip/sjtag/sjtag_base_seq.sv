// =============================================================================
// sjtag_base_seq.sv - SJTAG 基础 Sequence
//
// 所有 SJTAG sequence 的基类，提供常用的原子操作任务。
// =============================================================================

class sjtag_base_seq extends uvm_sequence #(sjtag_seq_item);
  `uvm_object_utils(sjtag_base_seq)

  function new(string name = "sjtag_base_seq");
    super.new(name);
  endfunction

  // -------------------------------------------------------------------------
  // 原子操作：TAP 复位
  // -------------------------------------------------------------------------
  task do_reset();
    sjtag_seq_item item;
    `uvm_do_with(item, { op == sjtag_seq_item::SJTAG_RESET; })
  endtask

  // -------------------------------------------------------------------------
  // 原子操作：APB 写
  // -------------------------------------------------------------------------
  task apb_write(logic [31:0] addr, logic [31:0] data);
    sjtag_seq_item item;
    `uvm_do_with(item, {
      op    == sjtag_seq_item::SJTAG_APB_WRITE;
      addr  == local::addr;
      wdata == local::data;
    })
  endtask

  // -------------------------------------------------------------------------
  // 原子操作：APB 读，rdata 从 rsp 返回
  // -------------------------------------------------------------------------
  task apb_read(logic [31:0] addr, output logic [31:0] rdata);
    sjtag_seq_item item;
    item = sjtag_seq_item::type_id::create("item");
    item.op   = sjtag_seq_item::SJTAG_APB_READ;
    item.addr = addr;
    start_item(item);
    finish_item(item);
    rdata = item.rdata;
  endtask

  // -------------------------------------------------------------------------
  // 原子操作：读 IDCODE
  // -------------------------------------------------------------------------
  task read_idcode(output logic [31:0] idcode);
    sjtag_seq_item item;
    item = sjtag_seq_item::type_id::create("item");
    item.op = sjtag_seq_item::SJTAG_IDCODE;
    start_item(item);
    finish_item(item);
    idcode = item.rdata;
  endtask

  // 子类重写 body
  virtual task body();
  endtask

endclass : sjtag_base_seq
