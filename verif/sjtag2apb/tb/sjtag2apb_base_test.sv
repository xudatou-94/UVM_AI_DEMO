// =============================================================================
// sjtag2apb_base_test.sv - sjtag2apb 测试基类
//
// 所有具体测试继承此类。基类负责：
//   1. 创建 sjtag2apb_env
//   2. 从 plusarg 读取时钟配置并传递给 env
//   3. 提供 run_seq() 钩子供派生类重写
//   4. 提供 sjtag_seq_start() 辅助任务简化 sequence 启动
// =============================================================================

class sjtag2apb_base_test extends uvm_test;
  `uvm_component_utils(sjtag2apb_base_test)

  // --------------------------------------------------------------------------
  // 环境句柄（派生测试类可直接访问）
  // --------------------------------------------------------------------------
  sjtag2apb_env env;

  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // --------------------------------------------------------------------------
  // build_phase：读取配置并创建环境
  // --------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    int unsigned tck_half_ns;
    super.build_phase(phase);

    // 从 plusarg 读取 TCK 半周期配置，默认 50ns（10MHz）
    tck_half_ns = 50;
    void'($value$plusargs("TCK_HALF_NS=%0d", tck_half_ns));
    uvm_config_db #(int unsigned)::set(this, "env", "tck_half_period_ns", tck_half_ns);

    env = sjtag2apb_env::type_id::create("env", this);
  endfunction

  // --------------------------------------------------------------------------
  // run_phase：统一的 objection 管理
  // --------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("BASE_TEST", $sformatf("测试开始：%s", get_type_name()), UVM_NONE)
    run_seq();
    // 等待 APB slave 处理完最后一笔事务（20 PCLK 约 200ns）
    #200ns;
    `uvm_info("BASE_TEST", $sformatf("测试结束：%s", get_type_name()), UVM_NONE)
    phase.drop_objection(this);
  endtask

  // --------------------------------------------------------------------------
  // run_seq：派生测试类重写此任务以启动各自的 sequence
  // --------------------------------------------------------------------------
  virtual task run_seq();
    // 基类默认不做任何操作
  endtask

  // --------------------------------------------------------------------------
  // sjtag_seq_start：辅助任务，设置 p_env 并启动 sequence
  // --------------------------------------------------------------------------
  task sjtag_seq_start(sjtag2apb_tb_base_seq seq);
    seq.p_env = env;
    seq.start(env.sjtag_agt.seqr);
  endtask

endclass : sjtag2apb_base_test
