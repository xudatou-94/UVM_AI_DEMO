// =============================================================================
// sjtag2apb_apb_wait_state_seq.sv
// case_id: sjtag2apb_0009 | case_name: sjtag2apb_apb_wait_state
//
// 验证 APB slave 插入不同等待状态（0/1/2/4/7 周期）时，DUT 能正确等待 PREADY
// 并完成事务，读写数据保持正确。
// =============================================================================

class sjtag2apb_apb_wait_state_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_apb_wait_state_seq)

  function new(string name = "sjtag2apb_apb_wait_state_seq");
    super.new(name);
  endfunction

  task body();
    // 待测等待状态值：0（无等待）/ 1 / 2 / 4 / 7（最大）
    int unsigned ws_list [5] = '{0, 1, 2, 4, 7};
    logic [31:0] addr, wdata, rdata;
    int unsigned pass_cnt = 0, fail_cnt = 0;

    `uvm_info("APB_WAIT_STATE",
      "=== TC sjtag2apb_0009: APB 等待状态验证 ===", UVM_NONE)

    do_reset();

    foreach(ws_list[i]) begin
      automatic int unsigned ws = ws_list[i];

      // 配置 APB slave 等待状态
      configure_slave_ws(ws);
      `uvm_info("APB_WAIT_STATE",
        $sformatf("设置 wait_states=%0d", ws), UVM_MEDIUM)

      // 随机地址和数据
      addr  = ($urandom_range(0, 15) * 4);
      wdata = $urandom();

      // 写操作（slave 将在 ws 个周期后拉高 PREADY）
      sjtag2apb_write(addr, wdata);

      // 读回校验
      sjtag2apb_read(addr, rdata);

      if (rdata !== wdata) begin
        fail_cnt++;
        `uvm_error("APB_WAIT_STATE",
          $sformatf("wait_states=%0d FAIL：addr=0x%08x 期望=0x%08x 实际=0x%08x",
                    ws, addr, wdata, rdata))
      end else begin
        pass_cnt++;
        `uvm_info("APB_WAIT_STATE",
          $sformatf("wait_states=%0d PASS：addr=0x%08x data=0x%08x", ws, addr, rdata),
          UVM_MEDIUM)
      end
    end

    // 恢复默认等待状态（0）
    configure_slave_ws(0);

    `uvm_info("APB_WAIT_STATE",
      $sformatf("=== TC sjtag2apb_0009 完成：%0d 通过 / %0d 失败 ===",
                pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_apb_wait_state_seq

// =============================================================================
class sjtag2apb_apb_wait_state_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_apb_wait_state_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_apb_wait_state_seq seq;
    seq = sjtag2apb_apb_wait_state_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_apb_wait_state_test
