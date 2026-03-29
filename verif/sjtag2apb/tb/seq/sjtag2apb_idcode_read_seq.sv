// =============================================================================
// sjtag2apb_idcode_read_seq.sv
// case_id: sjtag2apb_0003 | case_name: sjtag2apb_idcode_read
//
// 验证通过 INSTR_IDCODE 指令读取 IDCODE，数值与设计参数 32'h5A7B_0001 一致。
// 重复读取 10 次，确认结果稳定不变。
// =============================================================================

class sjtag2apb_idcode_read_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_idcode_read_seq)

  function new(string name = "sjtag2apb_idcode_read_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] idcode;
    int unsigned pass_cnt = 0;

    `uvm_info("IDCODE_READ", "=== TC sjtag2apb_0003: IDCODE 读取验证 ===", UVM_NONE)

    do_reset();

    // 重复读取 10 次，每次间隔随机 1~5 个 TCK 周期
    repeat(10) begin
      read_idcode(idcode);

      if (idcode !== 32'h5A7B_0001) begin
        `uvm_error("IDCODE_READ",
          $sformatf("IDCODE 不匹配：期望=0x5A7B_0001 实际=0x%08x", idcode))
      end else begin
        pass_cnt++;
        `uvm_info("IDCODE_READ",
          $sformatf("IDCODE 正确（第 %0d 次）：0x%08x", pass_cnt, idcode), UVM_MEDIUM)
      end

      // 随机等待 1~5 个 TCK 周期（100ns 每周期）
      #($urandom_range(1, 5) * 100ns);
    end

    `uvm_info("IDCODE_READ",
      $sformatf("=== TC sjtag2apb_0003 完成：%0d/10 次通过 ===", pass_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_idcode_read_seq

// =============================================================================
class sjtag2apb_idcode_read_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_idcode_read_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_idcode_read_seq seq;
    seq = sjtag2apb_idcode_read_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_idcode_read_test
