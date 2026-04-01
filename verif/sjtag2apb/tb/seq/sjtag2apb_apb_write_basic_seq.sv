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
    logic [31:0] addr_list[20];
    logic [31:0] wdata_list[20];
    logic [31:0] rdata;

    `uvm_info("APB_WRITE_BASIC", "=== TC sjtag2apb_0005: APB 基本写操作 ===", UVM_NONE)

    do_reset();

    // 第一阶段：执行 20 次随机写操作，记录地址/数据
    for (int i = 0; i < 20; i++) begin
      addr_list[i]  = {$urandom()} & 32'hFFFF_FFFC;  // 4 字节对齐
      wdata_list[i] = $urandom();
      sjtag2apb_write(addr_list[i], wdata_list[i]);
      `uvm_info("APB_WRITE_BASIC",
        $sformatf("写：addr=0x%08x data=0x%08x", addr_list[i], wdata_list[i]), UVM_HIGH)
    end

    wait_apb_cycles(5);

    // 第二阶段：逐一回读，由 scoreboard 比对写入值与读回值
    for (int i = 0; i < 20; i++) begin
      sjtag2apb_read(addr_list[i], rdata);
      `uvm_info("APB_WRITE_BASIC",
        $sformatf("读：addr=0x%08x rdata=0x%08x", addr_list[i], rdata), UVM_HIGH)
    end

    wait_apb_cycles(10);

    `uvm_info("APB_WRITE_BASIC", "=== TC sjtag2apb_0005 完成 ===", UVM_NONE)
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
