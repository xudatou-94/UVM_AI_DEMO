// =============================================================================
// sjtag2apb_apb_read_after_write_seq.sv
// case_id: sjtag2apb_0008 | case_name: sjtag2apb_apb_read_after_write
//
// 先写后读（write-then-read）验证，确认 CDC 路径上读写数据一致。
// 写后随机等待若干 TCK 周期，模拟 APB 事务完成 + CDC 同步完成的时延。
// =============================================================================

class sjtag2apb_apb_read_after_write_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_apb_read_after_write_seq)

  function new(string name = "sjtag2apb_apb_read_after_write_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] addr, wdata, rdata;
    int unsigned wait_ns;
    int unsigned pass_cnt = 0, fail_cnt = 0;

    `uvm_info("APB_RD_AFTER_WR",
      "=== TC sjtag2apb_0008: 先写后读一致性验证 ===", UVM_NONE)

    do_reset();

    // 执行 20 组先写后读，覆盖不同地址、数据和等待时间
    repeat(20) begin
      addr    = {$urandom()} & 32'hFFFF_FFFC;  // 4 字节对齐
      wdata   = $urandom();
      wait_ns = $urandom_range(2, 10) * 100;   // 随机等待 200ns~1000ns

      // 写操作
      apb_write(addr, wdata);

      // 随机等待（覆盖 CDC 同步时延）
      #(wait_ns * 1ns);

      // 读操作
      apb_read(addr, rdata);

      if (rdata !== wdata) begin
        fail_cnt++;
        `uvm_error("APB_RD_AFTER_WR",
          $sformatf("数据不一致：addr=0x%08x 写=0x%08x 读=0x%08x 等待=%0dns",
                    addr, wdata, rdata, wait_ns))
      end else begin
        pass_cnt++;
        `uvm_info("APB_RD_AFTER_WR",
          $sformatf("一致 [%0d]：addr=0x%08x data=0x%08x", pass_cnt, addr, rdata),
          UVM_HIGH)
      end
    end

    `uvm_info("APB_RD_AFTER_WR",
      $sformatf("=== TC sjtag2apb_0008 完成：%0d 通过 / %0d 失败 ===",
                pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_apb_read_after_write_seq

// =============================================================================
class sjtag2apb_apb_read_after_write_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_apb_read_after_write_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_apb_read_after_write_seq seq;
    seq = sjtag2apb_apb_read_after_write_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_apb_read_after_write_test
