// =============================================================================
// sjtag2apb_apb_write_basic_seq.sv
// case_id: sjtag2apb_0005 | case_name: sjtag2apb_apb_write_basic
//
// 验证基本 APB 写操作：20 次随机地址/数据写入，由 scoreboard 通过 APB monitor
// 校验 PADDR/PWDATA/PWRITE 与 seq_item 一致。
// =============================================================================

class sjtag2apb_apb_write_basic_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_apb_write_basic_seq)

  function new(string name = "sjtag2apb_apb_write_basic_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] addr, wdata;

    `uvm_info("APB_WRITE_BASIC", "=== TC sjtag2apb_0005: APB 基本写操作 ===", UVM_NONE)

    do_reset();

    // 执行 20 次随机写操作，覆盖不同地址和数据值
    repeat(20) begin
      addr  = {$urandom()} & 32'hFFFF_FFFC;  // 4 字节对齐
      wdata = $urandom();
      sjtag2apb_write(addr, wdata);
      `uvm_info("APB_WRITE_BASIC",
        $sformatf("APB 写：addr=0x%08x data=0x%08x", addr, wdata), UVM_HIGH)
    end

    // 等待 APB slave 完成最后一笔事务，scoreboard 完成记录
    wait_apb_cycles(10);

    `uvm_info("APB_WRITE_BASIC",
      "=== TC sjtag2apb_0005 完成，数据校验由 scoreboard 完成 ===", UVM_NONE)
  endtask

endclass : sjtag2apb_apb_write_basic_seq

// =============================================================================
class sjtag2apb_apb_write_basic_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_apb_write_basic_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_apb_write_basic_seq seq;
    seq = sjtag2apb_apb_write_basic_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_apb_write_basic_test
