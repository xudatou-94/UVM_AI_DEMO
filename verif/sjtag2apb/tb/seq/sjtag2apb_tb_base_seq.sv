// =============================================================================
// sjtag2apb_tb_base_seq.sv - sjtag2apb TB 级 Sequence 基类
//
// 继承自 sjtag_base_seq（VIP 提供），增加：
//   - p_env：指向 sjtag2apb_env 的句柄（由 base_test 在 start 前设置）
//   - wait_apb_cycles()：等待若干 PCLK 周期
//   - configure_slave_ws()：配置 APB slave 全局等待状态
//   - configure_slave_err()：配置 APB slave 地址级 PSLVERR 注入
//   - preload_slave()：预置 APB slave 内存读数据
//
// 以上辅助任务均通过 p_env.apb_slv_seq 访问 APB VIP slave sequence，
// 与 TLM FIFO 方案对应，不再依赖独立的 slave model 组件。
// =============================================================================

class sjtag2apb_tb_base_seq extends sjtag_base_seq;
  `uvm_object_utils(sjtag2apb_tb_base_seq)

  // 指向 env 的句柄，由 base_test 在 start() 前赋值
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
  // 配置 APB slave 默认等待状态数（立即生效，影响后续所有事务）
  // --------------------------------------------------------------------------
  task configure_slave_ws(int unsigned ws);
    if (p_env == null) begin
      `uvm_warning("TB_BASE_SEQ", "p_env 未设置，无法配置 slave wait_states")
      return;
    end
    p_env.apb_slv_seq.default_wait_states = ws;
  endtask

  // --------------------------------------------------------------------------
  // 使能或禁用指定地址的 PSLVERR 注入
  //   en=1: 该地址的后续事务返回 PSLVERR=1
  //   en=0: 清除注入，恢复正常响应
  // --------------------------------------------------------------------------
  task configure_slave_err(logic [31:0] addr, bit en);
    if (p_env == null) begin
      `uvm_warning("TB_BASE_SEQ", "p_env 未设置，无法配置 slave pslverr")
      return;
    end
    if (en)
      p_env.apb_slv_seq.pslverr_addrs[addr] = 1;
    else
      p_env.apb_slv_seq.pslverr_addrs.delete(addr);
  endtask

  // --------------------------------------------------------------------------
  // 预置 APB slave 内存：在读操作发生前写入期望返回数据
  // 等效于初始化 slave 内部存储器中的只读数据
  // --------------------------------------------------------------------------
  task preload_slave(logic [31:0] addr, logic [31:0] data);
    if (p_env == null) begin
      `uvm_warning("TB_BASE_SEQ", "p_env 未设置，无法预置 slave 内存")
      return;
    end
    p_env.apb_slv_seq.mem[addr] = data;
    `uvm_info("TB_BASE_SEQ",
      $sformatf("预置 slave mem[0x%08x] = 0x%08x", addr, data), UVM_HIGH)
  endtask

  virtual task body();
  endtask

endclass : sjtag2apb_tb_base_seq
