// =============================================================================
// sjtag2apb_tap_soft_reset_seq.sv
// case_id: sjtag2apb_0002 | case_name: sjtag2apb_tap_soft_reset
//
// 验证连续 5 个 TMS=1 软复位后 TAP 回到 TEST_LOGIC_RESET，后续事务正常执行。
// 重复在不同 TAP 中间状态下执行软复位，验证每次复位后 IDCODE 读取正确。
// =============================================================================

class sjtag2apb_tap_soft_reset_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_tap_soft_reset_seq)

  function new(string name = "sjtag2apb_tap_soft_reset_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] idcode;
    logic [31:0] addr, wdata;
    int unsigned n_ops;

    `uvm_info("TAP_SOFT_RESET", "=== TC sjtag2apb_0002: TAP 软复位验证 ===", UVM_NONE)

    repeat(5) begin
      // 随机执行 1~3 笔 APB 操作，使 TAP 处于不同的中间状态
      n_ops = $urandom_range(1, 3);
      repeat(n_ops) begin
        addr  = {$urandom() & 32'hFFFF_FFFC};
        wdata = $urandom();
        apb_write(addr, wdata);
      end

      // 执行软复位
      do_reset();
      `uvm_info("TAP_SOFT_RESET",
                $sformatf("软复位完成（前序操作 %0d 笔）", n_ops), UVM_MEDIUM)

      wait_apb_cycles(2);

      // 验证复位后 IDCODE
      read_idcode(idcode);
      if (idcode !== 32'h5A7B_0001) begin
        `uvm_error("TAP_SOFT_RESET",
          $sformatf("IDCODE 不匹配：期望=0x5A7B_0001 实际=0x%08x", idcode))
      end else begin
        `uvm_info("TAP_SOFT_RESET",
          $sformatf("软复位后 IDCODE 正确：0x%08x", idcode), UVM_MEDIUM)
      end
    end

    // 最终再做一次确认性读取
    do_reset();
    read_idcode(idcode);
    if (idcode !== 32'h5A7B_0001)
      `uvm_error("TAP_SOFT_RESET", "最终 IDCODE 校验失败")
    else
      `uvm_info("TAP_SOFT_RESET", "最终 IDCODE 校验通过", UVM_NONE)

    `uvm_info("TAP_SOFT_RESET", "=== TC sjtag2apb_0002 完成 ===", UVM_NONE)
  endtask

endclass : sjtag2apb_tap_soft_reset_seq

// =============================================================================
class sjtag2apb_tap_soft_reset_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_tap_soft_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_tap_soft_reset_seq seq;
    seq = sjtag2apb_tap_soft_reset_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_tap_soft_reset_test
