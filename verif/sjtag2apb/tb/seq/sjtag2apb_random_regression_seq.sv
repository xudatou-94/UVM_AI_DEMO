// =============================================================================
// sjtag2apb_random_regression_seq.sv
// case_id: sjtag2apb_0013 | case_name: sjtag2apb_random_regression
//
// 全随机回归激励：混合 APB 读/写/IDCODE/复位操作，随机注入等待状态和 PSLVERR，
// 使用 sequence 内置 shadow memory 对每笔读事务进行数据校验。
// 事务总数由 +TRANS_NUM plusarg 控制（默认 100）。
// =============================================================================

class sjtag2apb_random_regression_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_random_regression_seq)

  // sequence 内 shadow memory（镜像写入数据，用于读操作校验）
  logic [31:0] seq_shadow [logic [31:0]];

  // 记录已写过的地址（用于随机选择读地址）
  logic [31:0] written_addrs [$];

  function new(string name = "sjtag2apb_random_regression_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned n_trans   = 100;
    logic [31:0] addr, wdata, rdata, idcode;
    int unsigned op;
    int unsigned wait_ns;
    int unsigned pass_cnt  = 0;
    int unsigned fail_cnt  = 0;
    // PSLVERR 注入：约 5% 概率，每 20 笔触发一次
    logic [31:0] pslverr_addr = 32'hERR0_0000;
    bit          pslverr_active = 0;

    // 从 plusarg 读取事务数量
    void'($value$plusargs("TRANS_NUM=%0d", n_trans));

    `uvm_info("RANDOM_REGR",
      $sformatf("=== TC sjtag2apb_0013: 随机回归（%0d 笔事务）===", n_trans), UVM_NONE)

    do_reset();
    seq_shadow.delete();
    written_addrs.delete();

    for (int i = 0; i < n_trans; i++) begin

      // 随机决定是否插入 PSLVERR（约 5% 概率）
      if (!pslverr_active && ($urandom_range(0, 19) == 0)) begin
        pslverr_addr = {$urandom()} & 32'hFFFF_FFFC;
        configure_slave_err(pslverr_addr, 1);
        pslverr_active = 1;
        `uvm_info("RANDOM_REGR",
          $sformatf("[%0d] 注入 PSLVERR：addr=0x%08x", i, pslverr_addr), UVM_MEDIUM)
      end else if (pslverr_active) begin
        // 清除上一次的 PSLVERR 注入
        configure_slave_err(pslverr_addr, 0);
        pslverr_active = 0;
      end

      // 随机配置等待状态（0~3 周期）
      configure_slave_ws($urandom_range(0, 3));

      // 随机选择操作类型（写:读:IDCODE:复位 = 4:3:2:1 权重）
      op = $urandom_range(0, 9);

      if (op <= 3) begin
        // ---- 写操作 ----
        addr  = {$urandom()} & 32'hFFFF_FFFC;
        wdata = $urandom();
        // 避开 pslverr_addr（免得污染 shadow memory）
        if (pslverr_active && addr == pslverr_addr)
          addr = addr + 4;
        apb_write(addr, wdata);
        // 更新 shadow memory
        seq_shadow[addr] = wdata;
        if (!written_addrs.size() || written_addrs[$] != addr)
          written_addrs.push_back(addr);
        `uvm_info("RANDOM_REGR",
          $sformatf("[%0d] WRITE addr=0x%08x data=0x%08x", i, addr, wdata), UVM_HIGH)

      end else if (op <= 6) begin
        // ---- 读操作（优先选已写地址，确保有期望值可校验） ----
        if (written_addrs.size() > 0) begin
          // 随机选一个已写地址
          addr = written_addrs[$urandom_range(0, written_addrs.size()-1)];
          apb_read(addr, rdata);
          if (rdata !== seq_shadow[addr]) begin
            fail_cnt++;
            `uvm_error("RANDOM_REGR",
              $sformatf("[%0d] READ 不一致：addr=0x%08x 期望=0x%08x 实际=0x%08x",
                        i, addr, seq_shadow[addr], rdata))
          end else begin
            pass_cnt++;
            `uvm_info("RANDOM_REGR",
              $sformatf("[%0d] READ 正确：addr=0x%08x data=0x%08x", i, addr, rdata),
              UVM_HIGH)
          end
        end else begin
          // 还没有写过的地址，转为写操作
          addr  = {$urandom()} & 32'hFFFF_FFFC;
          wdata = $urandom();
          apb_write(addr, wdata);
          seq_shadow[addr] = wdata;
          written_addrs.push_back(addr);
        end

      end else if (op <= 8) begin
        // ---- IDCODE 读取 ----
        read_idcode(idcode);
        if (idcode !== 32'h5A7B_0001) begin
          fail_cnt++;
          `uvm_error("RANDOM_REGR",
            $sformatf("[%0d] IDCODE 不匹配：0x%08x", i, idcode))
        end else begin
          pass_cnt++;
          `uvm_info("RANDOM_REGR",
            $sformatf("[%0d] IDCODE 正确：0x%08x", i, idcode), UVM_HIGH)
        end

      end else begin
        // ---- 软复位（约 10% 概率） ----
        `uvm_info("RANDOM_REGR", $sformatf("[%0d] 软复位", i), UVM_MEDIUM)
        do_reset();
        // 复位后清空 shadow（DUT 内存保留，但 TAP 状态重置）
        // 注意：shadow memory 不清除，下次读操作仍可校验 slave 存储的值
      end

      // 随机事务间延迟（0~5 个 PCLK 周期）
      wait_apb_cycles($urandom_range(0, 5));
    end

    // 恢复默认配置
    configure_slave_ws(0);
    if (pslverr_active)
      configure_slave_err(pslverr_addr, 0);

    // 最终读取一次 IDCODE 确认 DUT 仍正常
    read_idcode(idcode);
    if (idcode !== 32'h5A7B_0001)
      `uvm_error("RANDOM_REGR", "最终 IDCODE 校验失败")

    `uvm_info("RANDOM_REGR",
      $sformatf("=== TC sjtag2apb_0013 完成：%0d 笔事务，校验 %0d 通过 / %0d 失败 ===",
                n_trans, pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_random_regression_seq

// =============================================================================
class sjtag2apb_random_regression_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_random_regression_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_random_regression_seq seq;
    seq = sjtag2apb_random_regression_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_random_regression_test
