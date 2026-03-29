// =============================================================================
// sjtag2apb_cdc_back2back_seq.sv
// case_id: sjtag2apb_0012 | case_name: sjtag2apb_cdc_back2back
//
// 验证背靠背（back-to-back）APB 事务时 toggle 同步器不丢脉冲。
// 以最小 TCK 间隔连续发送 N 笔事务，读回全部校验，确认无事务丢失。
// =============================================================================

class sjtag2apb_cdc_back2back_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_cdc_back2back_seq)

  function new(string name = "sjtag2apb_cdc_back2back_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned     n;
    logic [31:0]     addr_arr [];
    logic [31:0]     data_arr [];
    logic [31:0]     rdata;
    int unsigned     pass_cnt = 0, fail_cnt = 0;

    `uvm_info("CDC_BACK2BACK",
      "=== TC sjtag2apb_0012: CDC 背靠背事务验证 ===", UVM_NONE)

    do_reset();

    // 随机事务数量（4~8）
    n = $urandom_range(4, 8);
    addr_arr = new[n];
    data_arr = new[n];

    // 生成不重叠的地址和随机数据
    for (int i = 0; i < n; i++) begin
      addr_arr[i] = (i * 4);
      data_arr[i] = $urandom();
    end

    `uvm_info("CDC_BACK2BACK",
      $sformatf("背靠背写入 %0d 笔事务（无额外延迟）", n), UVM_MEDIUM)

    // 背靠背连续写：sjtag_base_seq 内部不插入额外延迟，事务直接连续提交
    for (int i = 0; i < n; i++) begin
      apb_write(addr_arr[i], data_arr[i]);
    end

    // 等待所有事务经 CDC 传播完毕（PCLK domain 稳定）
    wait_apb_cycles(20);

    // 逐一读回校验
    for (int i = 0; i < n; i++) begin
      apb_read(addr_arr[i], rdata);
      if (rdata !== data_arr[i]) begin
        fail_cnt++;
        `uvm_error("CDC_BACK2BACK",
          $sformatf("事务 [%0d] 数据不一致：addr=0x%08x 期望=0x%08x 实际=0x%08x",
                    i, addr_arr[i], data_arr[i], rdata))
      end else begin
        pass_cnt++;
        `uvm_info("CDC_BACK2BACK",
          $sformatf("事务 [%0d] 正确：addr=0x%08x data=0x%08x", i, addr_arr[i], rdata),
          UVM_HIGH)
      end
    end

    `uvm_info("CDC_BACK2BACK",
      $sformatf("=== TC sjtag2apb_0012 完成：%0d 笔事务，%0d 通过 / %0d 失败 ===",
                n, pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_cdc_back2back_seq

// =============================================================================
class sjtag2apb_cdc_back2back_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_cdc_back2back_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_cdc_back2back_seq seq;
    seq = sjtag2apb_cdc_back2back_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_cdc_back2back_test
