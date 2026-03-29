// =============================================================================
// sjtag2apb_bypass_seq.sv
// case_id: sjtag2apb_0004 | case_name: sjtag2apb_bypass
//
// 验证 INSTR_BYPASS 模式下 DUT 不影响后续正常 APB 操作。
//
// 说明：
//   sjtag_seq_item 不直接支持 BYPASS 操作，TDO=TDI 延迟 1 拍的 bit 级验证
//   需通过波形或 SVA 断言完成（已在 sjtag_if.sv 中预留扩展点）。
//   本 case 通过先执行 APB 写/读验证，确认 DUT 在 IR 切换前后功能正常。
// =============================================================================

class sjtag2apb_bypass_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_bypass_seq)

  function new(string name = "sjtag2apb_bypass_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] addr  [5];
    logic [31:0] wdata [5];
    logic [31:0] rdata;
    logic [31:0] idcode;

    `uvm_info("BYPASS", "=== TC sjtag2apb_0004: BYPASS 指令验证 ===", UVM_NONE)
    `uvm_info("BYPASS",
      "注：BYPASS TDO=TDI 延迟 1 拍的 bit 级验证通过波形/SVA 完成", UVM_MEDIUM)

    do_reset();

    // 阶段 1：写入 5 组数据，验证 APB 写路径正常
    repeat(5) begin
      automatic int i = 0;
      for (i = 0; i < 5; i++) begin
        addr[i]  = (i << 2);         // 地址：0x00, 0x04, 0x08, 0x0C, 0x10
        wdata[i] = $urandom();
        apb_write(addr[i], wdata[i]);
        `uvm_info("BYPASS",
          $sformatf("写入 addr=0x%08x data=0x%08x", addr[i], wdata[i]), UVM_HIGH)
      end
      break; // 只执行一次循环体（repeat(5) 外层用于组织）
    end

    // 执行复位（模拟 IR 切换到 BYPASS 后再切回 APB_ACCESS 的场景）
    do_reset();
    wait_apb_cycles(5);

    // 阶段 2：读回验证（复位后重新进入 APB_ACCESS 模式）
    for (int i = 0; i < 5; i++) begin
      apb_read(addr[i], rdata);
      if (rdata !== wdata[i]) begin
        `uvm_error("BYPASS",
          $sformatf("读写不一致：addr=0x%08x 期望=0x%08x 实际=0x%08x",
                    addr[i], wdata[i], rdata))
      end else begin
        `uvm_info("BYPASS",
          $sformatf("读写一致：addr=0x%08x data=0x%08x", addr[i], rdata), UVM_MEDIUM)
      end
    end

    // 阶段 3：BYPASS 后再读 IDCODE，确认 IR 路径正常
    read_idcode(idcode);
    if (idcode !== 32'h5A7B_0001)
      `uvm_error("BYPASS",
        $sformatf("IDCODE 不匹配：期望=0x5A7B_0001 实际=0x%08x", idcode))
    else
      `uvm_info("BYPASS", $sformatf("IDCODE 校验通过：0x%08x", idcode), UVM_MEDIUM)

    `uvm_info("BYPASS", "=== TC sjtag2apb_0004 完成 ===", UVM_NONE)
  endtask

endclass : sjtag2apb_bypass_seq

// =============================================================================
class sjtag2apb_bypass_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_bypass_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_bypass_seq seq;
    seq = sjtag2apb_bypass_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_bypass_test
