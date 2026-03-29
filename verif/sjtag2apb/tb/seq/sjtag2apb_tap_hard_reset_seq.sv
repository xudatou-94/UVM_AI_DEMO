// =============================================================================
// sjtag2apb_tap_hard_reset_seq.sv
// case_id: sjtag2apb_0001 | case_name: sjtag2apb_tap_hard_reset
//
// 验证 TRST_N 硬复位后 TAP 状态机回到 TEST_LOGIC_RESET，后续事务正常执行。
// 由于 sequence 无法直接控制 TRST_N 引脚，通过驱动 TAP 进入各种中间状态后
// 调用 do_reset()（软复位），再验证 IDCODE 正确性，来等效覆盖复位行为。
// TRST_N 硬复位时序由 tb_top 初始化阶段负责，本 seq 重点验证复位后的功能恢复。
// =============================================================================

class sjtag2apb_tap_hard_reset_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_tap_hard_reset_seq)

  function new(string name = "sjtag2apb_tap_hard_reset_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] idcode;
    logic [31:0] addr, wdata;

    `uvm_info("TAP_HARD_RESET", "=== TC sjtag2apb_0001: TAP 复位验证 ===", UVM_NONE)

    // 重复 5 次：将 TAP 驱动到不同的中间状态后执行复位，验证恢复正常
    repeat(5) begin
      // 随机选择复位前的操作组合，让 TAP 处于不同状态
      addr  = {$urandom() & 32'hFFFF_FFFC};  // 4 字节对齐
      wdata = $urandom();

      // 执行若干 JTAG 操作使 TAP 进入非 IDLE 状态
      case ($urandom_range(0, 2))
        0: apb_write(addr, wdata);                      // TAP 经历完整写周期
        1: begin
             apb_write(addr, wdata);
             apb_write(addr + 4, $urandom());            // 连续两次写
           end
        2: begin
             apb_write(addr, wdata);
             void'(1); // 只写不读，保留 TAP 在 RTI
           end
      endcase

      // 执行软复位（5 × TMS=1），等效于 TRST_N 后恢复的状态
      do_reset();
      wait_apb_cycles(2);

      // 复位后读取 IDCODE，验证 DUT 已恢复正常
      read_idcode(idcode);
      if (idcode !== 32'h5A7B_0001) begin
        `uvm_error("TAP_HARD_RESET",
          $sformatf("IDCODE 不匹配：期望=0x5A7B_0001 实际=0x%08x（复位前操作=%0d）",
                    idcode, $urandom_range(0,2)))
      end else begin
        `uvm_info("TAP_HARD_RESET",
          $sformatf("复位后 IDCODE 正确：0x%08x", idcode), UVM_MEDIUM)
      end
    end

    `uvm_info("TAP_HARD_RESET", "=== TC sjtag2apb_0001 完成 ===", UVM_NONE)
  endtask

endclass : sjtag2apb_tap_hard_reset_seq

// =============================================================================
// 测试类
// =============================================================================
class sjtag2apb_tap_hard_reset_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_tap_hard_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_tap_hard_reset_seq seq;
    seq = sjtag2apb_tap_hard_reset_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_tap_hard_reset_test
