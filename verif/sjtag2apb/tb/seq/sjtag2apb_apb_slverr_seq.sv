// =============================================================================
// sjtag2apb_apb_slverr_seq.sv
// case_id: sjtag2apb_0010 | case_name: sjtag2apb_apb_slverr
//
// 验证 APB slave 返回 PSLVERR=1 时，DUT 不死锁，后续事务可正常执行。
// 分别测试写事务触发和读事务触发 PSLVERR 两种场景。
// =============================================================================

class sjtag2apb_apb_slverr_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_apb_slverr_seq)

  function new(string name = "sjtag2apb_apb_slverr_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] err_addr  = 32'hDEAD_0000;   // 触发 PSLVERR 的地址
    logic [31:0] norm_addr;
    logic [31:0] wdata, rdata;
    int unsigned pass_cnt = 0, fail_cnt = 0;

    `uvm_info("APB_SLVERR", "=== TC sjtag2apb_0010: APB PSLVERR 响应验证 ===", UVM_NONE)

    do_reset();

    // ---- 场景 1：写事务触发 PSLVERR ----
    `uvm_info("APB_SLVERR", "场景 1：写事务触发 PSLVERR", UVM_MEDIUM)
    configure_slave_err(err_addr, 1);
    sjtag2apb_write(err_addr, 32'hBAD_0000);   // PSLVERR 触发，DUT 应不死锁
    wait_apb_cycles(5);

    // ---- 场景 2：读事务触发 PSLVERR ----
    `uvm_info("APB_SLVERR", "场景 2：读事务触发 PSLVERR", UVM_MEDIUM)
    sjtag2apb_read(err_addr, rdata);           // PSLVERR 触发，rdata 为无效值
    wait_apb_cycles(5);

    // ---- 验证后续正常事务不受影响 ----
    `uvm_info("APB_SLVERR", "验证 PSLVERR 后 DUT 正常工作", UVM_MEDIUM)
    configure_slave_err(err_addr, 0);    // 清除错误注入

    for (int i = 0; i < 5; i++) begin
      norm_addr = ($urandom_range(1, 15) * 4);   // 避开 err_addr
      wdata     = $urandom();
      sjtag2apb_write(norm_addr, wdata);
      sjtag2apb_read(norm_addr, rdata);

      if (rdata !== wdata) begin
        fail_cnt++;
        `uvm_error("APB_SLVERR",
          $sformatf("PSLVERR 后数据不一致 [%0d]：addr=0x%08x 期望=0x%08x 实际=0x%08x",
                    i, norm_addr, wdata, rdata))
      end else begin
        pass_cnt++;
        `uvm_info("APB_SLVERR",
          $sformatf("PSLVERR 后正常 [%0d]：addr=0x%08x data=0x%08x", i, norm_addr, rdata),
          UVM_HIGH)
      end
    end

    // ---- 场景 3：连续两次 PSLVERR ----
    `uvm_info("APB_SLVERR", "场景 3：连续两次 PSLVERR", UVM_MEDIUM)
    configure_slave_err(err_addr, 1);
    sjtag2apb_write(err_addr, 32'hDEAD_0001);
    sjtag2apb_write(err_addr, 32'hDEAD_0002);
    wait_apb_cycles(5);
    configure_slave_err(err_addr, 0);

    // 再次确认 DUT 正常工作
    norm_addr = 32'h0000_0100;
    wdata     = 32'hC0DE_C0DE;
    sjtag2apb_write(norm_addr, wdata);
    sjtag2apb_read(norm_addr, rdata);
    if (rdata !== wdata) begin
      fail_cnt++;
      `uvm_error("APB_SLVERR", "连续 PSLVERR 后 DUT 功能异常")
    end else begin
      pass_cnt++;
      `uvm_info("APB_SLVERR", "连续 PSLVERR 后 DUT 功能正常", UVM_MEDIUM)
    end

    `uvm_info("APB_SLVERR",
      $sformatf("=== TC sjtag2apb_0010 完成：%0d 通过 / %0d 失败 ===",
                pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_apb_slverr_seq

// =============================================================================
class sjtag2apb_apb_slverr_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_apb_slverr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_apb_slverr_seq seq;
    seq = sjtag2apb_apb_slverr_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_apb_slverr_test
