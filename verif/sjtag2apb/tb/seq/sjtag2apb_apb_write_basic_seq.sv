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
    logic [31:0] addr, wdata, rdata;
    int unsigned pass_cnt = 0, fail_cnt = 0;

    `uvm_info("APB_WRITE_BASIC", "=== TC sjtag2apb_0005: APB 基本写操作 ===", UVM_NONE)

    do_reset();

    // 每次写完立即回读，slave 只保存一拍数据
    repeat(20) begin
      addr  = {$urandom()} & 32'hFFFF_FFFC;
      wdata = $urandom();

      sjtag2apb_write(addr, wdata);
      sjtag2apb_read(addr, rdata);

      if (rdata !== wdata) begin
        fail_cnt++;
        `uvm_error("APB_WRITE_BASIC",
          $sformatf("读写不一致：addr=0x%08x 写=0x%08x 读=0x%08x", addr, wdata, rdata))
      end else begin
        pass_cnt++;
        `uvm_info("APB_WRITE_BASIC",
          $sformatf("一致：addr=0x%08x data=0x%08x", addr, rdata), UVM_HIGH)
      end
    end

    wait_apb_cycles(5);

    `uvm_info("APB_WRITE_BASIC",
      $sformatf("=== TC sjtag2apb_0005 完成：%0d 通过 / %0d 失败 ===",
                pass_cnt, fail_cnt), UVM_NONE)
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
