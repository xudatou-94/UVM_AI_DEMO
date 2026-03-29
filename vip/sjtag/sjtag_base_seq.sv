// =============================================================================
// sjtag_base_seq.sv - SJTAG 基础 Sequence
//
// 所有 SJTAG sequence 的基类，提供常用的原子操作任务。
//
// 命名说明：
//   sjtag2apb_write / sjtag2apb_read 明确表示这是通过 SJTAG 协议（TAP 状态机
//   + DR 移位）间接发起的 APB 事务，区别于 APB VIP 直接驱动总线的操作。
// =============================================================================

class sjtag_base_seq extends uvm_sequence #(sjtag_seq_item);
  `uvm_object_utils(sjtag_base_seq)

  function new(string name = "sjtag_base_seq");
    super.new(name);
  endfunction

  // -------------------------------------------------------------------------
  // 原子操作：TAP 复位（5 个 TMS=1）
  // -------------------------------------------------------------------------
  task do_reset();
    sjtag_seq_item item;
    `uvm_do_with(item, { op == sjtag_seq_item::SJTAG_RESET; })
  endtask

  // -------------------------------------------------------------------------
  // 原子操作：通过 SJTAG 协议发起 APB 写
  //   内部流程：shift IR(APB_ACCESS) → shift DR({1,addr,data}) → UPDATE_DR
  //   DUT 在 UPDATE_DR 后自动发起 APB 写事务
  // -------------------------------------------------------------------------
  task sjtag2apb_write(logic [31:0] addr, logic [31:0] data);
    sjtag_seq_item item;
    `uvm_do_with(item, {
      op    == sjtag_seq_item::SJTAG_APB_WRITE;
      addr  == local::addr;
      wdata == local::data;
    })
  endtask

  // -------------------------------------------------------------------------
  // 原子操作：通过 SJTAG 协议发起 APB 读，读回值由 rdata 返回
  //   内部流程：第一次 DR 扫描发送读地址 → 等待 DUT 完成 APB 读事务
  //             第二次 DR 扫描 CAPTURE_DR 捕获 PRDATA → 移出 TDO
  // -------------------------------------------------------------------------
  task sjtag2apb_read(logic [31:0] addr, output logic [31:0] rdata);
    sjtag_seq_item item;
    item = sjtag_seq_item::type_id::create("item");
    item.op   = sjtag_seq_item::SJTAG_APB_READ;
    item.addr = addr;
    start_item(item);
    finish_item(item);
    rdata = item.rdata;
  endtask

  // -------------------------------------------------------------------------
  // 原子操作：读取 IDCODE 寄存器
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
