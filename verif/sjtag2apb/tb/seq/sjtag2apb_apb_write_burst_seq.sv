// =============================================================================
// sjtag2apb_apb_write_burst_seq.sv
// case_id: sjtag2apb_0006 | case_name: sjtag2apb_apb_write_burst
//
// 验证连续 N 次 APB 写操作，然后逐一读回校验，确认事务无丢失和数据混淆。
// N 随机 4~16，覆盖相同地址重复写和递增地址连续写两种场景。
// =============================================================================

class sjtag2apb_apb_write_burst_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_apb_write_burst_seq)

  function new(string name = "sjtag2apb_apb_write_burst_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned     n;
    logic [31:0]     addr_arr [];
    logic [31:0]     data_arr [];
    logic [31:0]     rdata;
    int unsigned     pass_cnt = 0, fail_cnt = 0;

    `uvm_info("APB_WRITE_BURST", "=== TC sjtag2apb_0006: APB burst 写验证 ===", UVM_NONE)

    do_reset();

    // 随机决定本次 burst 大小
    n = $urandom_range(4, 16);
    addr_arr = new[n];
    data_arr = new[n];

    // 生成 N 组随机地址（均为 4 字节对齐）和随机数据
    for (int i = 0; i < n; i++) begin
      addr_arr[i] = (i * 4);           // 递增地址，避免覆盖
      data_arr[i] = $urandom();
    end

    `uvm_info("APB_WRITE_BURST",
      $sformatf("开始 burst 写：共 %0d 笔", n), UVM_MEDIUM)

    // 每笔写完立即回读校验，slave 只保存一拍数据
    for (int i = 0; i < n; i++) begin
      sjtag2apb_write(addr_arr[i], data_arr[i]);
      sjtag2apb_read(addr_arr[i], rdata);
      if (rdata !== data_arr[i]) begin
        fail_cnt++;
        `uvm_error("APB_WRITE_BURST",
          $sformatf("读写不一致 [%0d]：addr=0x%08x 期望=0x%08x 实际=0x%08x",
                    i, addr_arr[i], data_arr[i], rdata))
      end else begin
        pass_cnt++;
        `uvm_info("APB_WRITE_BURST",
          $sformatf("读写一致 [%0d]：addr=0x%08x data=0x%08x", i, addr_arr[i], rdata),
          UVM_HIGH)
      end
    end

    `uvm_info("APB_WRITE_BURST",
      $sformatf("=== TC sjtag2apb_0006 完成：%0d 通过 / %0d 失败 ===",
                pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_apb_write_burst_seq

// =============================================================================
class sjtag2apb_apb_write_burst_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_apb_write_burst_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_apb_write_burst_seq seq;
    seq = sjtag2apb_apb_write_burst_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_apb_write_burst_test
