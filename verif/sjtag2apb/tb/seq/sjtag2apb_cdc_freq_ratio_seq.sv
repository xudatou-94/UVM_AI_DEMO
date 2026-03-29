// =============================================================================
// sjtag2apb_cdc_freq_ratio_seq.sv
// case_id: sjtag2apb_0011 | case_name: sjtag2apb_cdc_freq_ratio
//
// 验证不同 TCK/PCLK 频率比下 APB 读写事务的正确性。
// 各频率组合通过仿真命令行参数切换（+TCK_HALF_NS / +PCLK_HALF_NS），
// 本 sequence 验证在当前频率配置下 30 组随机读写均正确。
//
// 推荐运行方式：
//   make run TC=sjtag2apb_cdc_freq_ratio SEED=1 ...+TCK_HALF_NS=100+PCLK_HALF_NS=5  (1:20)
//   make run TC=sjtag2apb_cdc_freq_ratio SEED=1 ...+TCK_HALF_NS=50+PCLK_HALF_NS=5   (1:10)
//   make run TC=sjtag2apb_cdc_freq_ratio SEED=1 ...+TCK_HALF_NS=25+PCLK_HALF_NS=5   (1:5)
// =============================================================================

class sjtag2apb_cdc_freq_ratio_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_cdc_freq_ratio_seq)

  function new(string name = "sjtag2apb_cdc_freq_ratio_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] addr, wdata, rdata, idcode;
    int unsigned tck_half_ns = 50;
    int unsigned pass_cnt = 0, fail_cnt = 0;

    void'($value$plusargs("TCK_HALF_NS=%0d", tck_half_ns));

    `uvm_info("CDC_FREQ",
      $sformatf("=== TC sjtag2apb_0011: CDC 频率比验证（TCK 半周期=%0dns）===",
                tck_half_ns), UVM_NONE)

    do_reset();

    // 执行 30 组随机写后读回校验
    repeat(30) begin
      addr  = {$urandom()} & 32'hFFFF_FFFC;
      wdata = $urandom();

      apb_write(addr, wdata);
      apb_read(addr, rdata);

      if (rdata !== wdata) begin
        fail_cnt++;
        `uvm_error("CDC_FREQ",
          $sformatf("数据不一致：addr=0x%08x 写=0x%08x 读=0x%08x", addr, wdata, rdata))
      end else begin
        pass_cnt++;
      end
    end

    // 额外执行 10 次 IDCODE 读取，验证 IR 路径在不同频率下正常
    repeat(10) begin
      read_idcode(idcode);
      if (idcode !== 32'h5A7B_0001) begin
        fail_cnt++;
        `uvm_error("CDC_FREQ",
          $sformatf("IDCODE 不匹配：期望=0x5A7B_0001 实际=0x%08x", idcode))
      end else begin
        pass_cnt++;
      end
    end

    `uvm_info("CDC_FREQ",
      $sformatf("=== TC sjtag2apb_0011 完成（TCK半周期=%0dns）：%0d 通过 / %0d 失败 ===",
                tck_half_ns, pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_cdc_freq_ratio_seq

// =============================================================================
class sjtag2apb_cdc_freq_ratio_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_cdc_freq_ratio_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_cdc_freq_ratio_seq seq;
    seq = sjtag2apb_cdc_freq_ratio_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_cdc_freq_ratio_test
