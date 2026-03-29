// =============================================================================
// sjtag2apb_tb_base_seq.sv - sjtag2apb TB 级 Sequence 基类
//
// 继承自 sjtag_base_seq（VIP 提供的原子操作基类），增加：
//   - p_env：指向 sjtag2apb_env 的句柄，用于访问 apb_slave 配置
//   - wait_apb_cycles()：等待若干 PCLK 周期
//   - configure_slave_ws()：配置 APB slave 等待状态
//   - configure_slave_err()：配置 APB slave PSLVERR 注入
// =============================================================================

class sjtag2apb_tb_base_seq extends sjtag_base_seq;
  `uvm_object_utils(sjtag2apb_tb_base_seq)

  // --------------------------------------------------------------------------
  // 指向 env 的句柄，由 base_test 在 start 前设置
  // --------------------------------------------------------------------------
  sjtag2apb_env p_env;

  function new(string name = "sjtag2apb_tb_base_seq");
    super.new(name);
  endfunction

  // --------------------------------------------------------------------------
  // 等待若干 PCLK 周期（PCLK 默认 100MHz，每周期 10ns）
  // --------------------------------------------------------------------------
  task wait_apb_cycles(int unsigned n);
    #(n * 10ns);
  endtask

  // --------------------------------------------------------------------------
  // 配置 APB slave 默认等待状态数
  // --------------------------------------------------------------------------
  task configure_slave_ws(int unsigned ws);
    if (p_env == null) begin
      `uvm_warning("TB_BASE_SEQ", "p_env 未设置，无法配置 slave wait_states")
      return;
    end
    p_env.apb_slave.default_wait_states = ws;
  endtask

  // --------------------------------------------------------------------------
  // 使能/禁用指定地址的 PSLVERR 注入
  // --------------------------------------------------------------------------
  task configure_slave_err(logic [31:0] addr, bit en);
    if (p_env == null) begin
      `uvm_warning("TB_BASE_SEQ", "p_env 未设置，无法配置 slave pslverr")
      return;
    end
    if (en)
      p_env.apb_slave.pslverr_addrs[addr] = 1;
    else
      p_env.apb_slave.pslverr_addrs.delete(addr);
  endtask

  virtual task body();
  endtask

endclass : sjtag2apb_tb_base_seq
