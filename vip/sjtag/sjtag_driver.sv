// =============================================================================
// sjtag_driver.sv - SJTAG Master Driver
//
// 功能：
//   将 sjtag_seq_item 翻译为 JTAG 引脚时序，驱动 DUT 的 JTAG 端口。
//   内部维护 TAP 状态机当前状态，按需导航至目标状态。
//
// TAP 导航说明（从 RUN_TEST_IDLE 出发）：
//   → SHIFT_IR  : TMS=1,1,0,0
//   → SHIFT_DR  : TMS=1,0,0
//   SHIFT_IR/DR → UPDATE_IR/DR : 最后一位 TMS=1，再 TMS=1
//   UPDATE → RUN_TEST_IDLE     : TMS=0
//
// 移位规则：LSB first（bit0 先移出/入）
// TDO 在 TCK 下降沿更新，在 TCK 上升沿后采样
// =============================================================================

class sjtag_driver extends uvm_driver #(sjtag_seq_item);
  `uvm_component_utils(sjtag_driver)

  // -------------------------------------------------------------------------
  // 虚接口
  // -------------------------------------------------------------------------
  virtual sjtag_if vif;

  // -------------------------------------------------------------------------
  // 可配置参数
  // -------------------------------------------------------------------------
  int unsigned tck_half_period_ns = 50;  // TCK 半周期，默认 100ns（10MHz）

  // -------------------------------------------------------------------------
  // 内部 TAP 状态追踪
  // -------------------------------------------------------------------------
  typedef enum logic [3:0] {
    S_TEST_LOGIC_RESET = 4'h0, S_RUN_TEST_IDLE = 4'h1,
    S_SELECT_DR        = 4'h2, S_CAPTURE_DR    = 4'h3,
    S_SHIFT_DR         = 4'h4, S_EXIT1_DR      = 4'h5,
    S_PAUSE_DR         = 4'h6, S_EXIT2_DR      = 4'h7,
    S_UPDATE_DR        = 4'h8, S_SELECT_IR     = 4'h9,
    S_CAPTURE_IR       = 4'hA, S_SHIFT_IR      = 4'hB,
    S_EXIT1_IR         = 4'hC, S_PAUSE_IR      = 4'hD,
    S_EXIT2_IR         = 4'hE, S_UPDATE_IR     = 4'hF
  } drv_tap_state_e;

  drv_tap_state_e cur_state;

  // -------------------------------------------------------------------------
  // 构造函数 & build_phase
  // -------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual sjtag_if)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "sjtag_driver: 未获取到 virtual sjtag_if")
  endfunction

  // -------------------------------------------------------------------------
  // run_phase：初始化后循环处理事务
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    // 初始化引脚
    vif.tck   = 0;
    vif.trst_n = 0;
    vif.tms   = 1;
    vif.tdi   = 0;
    // 硬复位，持续 2 个 TCK 周期
    repeat(4) #(tck_half_period_ns * 1ns);
    vif.trst_n = 1;
    cur_state  = S_TEST_LOGIC_RESET;
    // 导航到 RUN_TEST_IDLE
    tap_goto_rti();

    forever begin
      sjtag_seq_item req;
      seq_item_port.get_next_item(req);
      `uvm_info("SJTAG_DRV", $sformatf("执行: %s", req.convert2string()), UVM_MEDIUM)

      // 直接回写到 req，sequence 在 finish_item() 返回后即可读到更新值
      case (req.op)
        sjtag_seq_item::SJTAG_RESET     : do_tap_reset();
        sjtag_seq_item::SJTAG_APB_WRITE : do_apb_write(req.addr, req.wdata);
        sjtag_seq_item::SJTAG_APB_READ  : do_apb_read(req.addr, req.rdata);
        sjtag_seq_item::SJTAG_IDCODE    : do_idcode(req.rdata);
        default: `uvm_error("SJTAG_DRV", "未知操作类型")
      endcase

      seq_item_port.item_done();  // 不带响应参数，避免响应队列积压
    end
  endtask

  // ===========================================================================
  // 高层操作任务
  // ===========================================================================

  // TAP 复位（TMS 连续 5 个 1）
  task do_tap_reset();
    repeat(5) tck_pulse(1, 0);
    tck_pulse(0, 0);              // 进入 RUN_TEST_IDLE
    cur_state = S_RUN_TEST_IDLE;
    `uvm_info("SJTAG_DRV", "TAP 复位完成", UVM_HIGH)
  endtask

  // APB 写操作
  task do_apb_write(logic [31:0] addr, logic [31:0] data);
    logic [63:0] dr_unused;
    // DR 格式：[64]=1(写), [63:32]=addr, [31:0]=data
    logic [64:0] dr_in = {1'b1, addr, data};
    shift_ir(4'h2);               // INSTR_APB_ACCESS
    shift_dr(dr_in, 65, dr_unused);
    tap_goto_rti();
    `uvm_info("SJTAG_DRV",
              $sformatf("APB Write: addr=0x%08x data=0x%08x", addr, data), UVM_HIGH)
  endtask

  // APB 读操作（先发地址，再 CAPTURE_DR 取回数据）
  task do_apb_read(logic [31:0] addr, output logic [31:0] rdata);
    logic [64:0] dr_out;
    logic [64:0] dr_in;
    // 第一次 DR 扫描：发送读请求（RW=0）
    dr_in = {1'b0, addr, 32'h0};
    shift_ir(4'h2);
    shift_dr(dr_in, 65, dr_out);
    tap_goto_rti();
    // 等待 DUT 完成 APB 事务（保守等待，可通过 PREADY 等方式优化）
    repeat(20) tck_pulse(0, 0);
    // 第二次 DR 扫描：CAPTURE_DR 时 DUT 将读数据装入 DR，移出读数据
    shift_ir(4'h2);
    shift_dr(dr_in, 65, dr_out);
    tap_goto_rti();
    rdata = dr_out[31:0];
    `uvm_info("SJTAG_DRV",
              $sformatf("APB Read:  addr=0x%08x rdata=0x%08x", addr, rdata), UVM_HIGH)
  endtask

  // 读取 IDCODE
  task do_idcode(output logic [31:0] idcode);
    logic [64:0] dr_out;
    shift_ir(4'h1);               // INSTR_IDCODE
    shift_dr(65'h0, 32, dr_out);  // 移出 32bit IDCODE
    tap_goto_rti();
    idcode = dr_out[31:0];
    `uvm_info("SJTAG_DRV", $sformatf("IDCODE = 0x%08x", idcode), UVM_HIGH)
  endtask

  // ===========================================================================
  // TAP 导航任务
  // ===========================================================================

  // 从当前状态导航到 RUN_TEST_IDLE
  task tap_goto_rti();
    case (cur_state)
      S_RUN_TEST_IDLE    : ;  // 已在 RTI，无需操作
      S_UPDATE_DR,
      S_UPDATE_IR        : begin tck_pulse(0, 0); cur_state = S_RUN_TEST_IDLE; end
      S_TEST_LOGIC_RESET : begin tck_pulse(0, 0); cur_state = S_RUN_TEST_IDLE; end
      default: begin
        // 通用路径：先复位，再回 RTI
        do_tap_reset();
      end
    endcase
  endtask

  // 移入 IR（从 RUN_TEST_IDLE 出发）
  task shift_ir(logic [3:0] ir_val);
    tap_goto_rti();
    // RTI → SELECT_DR → SELECT_IR → CAPTURE_IR → SHIFT_IR
    tck_pulse(1, 0); cur_state = S_SELECT_DR;
    tck_pulse(1, 0); cur_state = S_SELECT_IR;
    tck_pulse(0, 0); cur_state = S_CAPTURE_IR;
    tck_pulse(0, 0); cur_state = S_SHIFT_IR;
    // 移入 IR（4bit，LSB first；最后一位 TMS=1 退出）
    for (int i = 0; i < 3; i++) begin
      tck_pulse(0, ir_val[i]);  // SHIFT_IR
    end
    tck_pulse(1, ir_val[3]);    // EXIT1_IR（最后一位）
    cur_state = S_EXIT1_IR;
    // EXIT1_IR → UPDATE_IR
    tck_pulse(1, 0); cur_state = S_UPDATE_IR;
    `uvm_info("SJTAG_DRV", $sformatf("IR = 4'h%0x", ir_val), UVM_HIGH)
  endtask

  // 移入/移出 DR（从 UPDATE_IR 或 RUN_TEST_IDLE 出发）
  task shift_dr(logic [64:0] dr_in, int dr_len,
                output logic [64:0] dr_out);
    dr_out = '0;
    // 导航到 SHIFT_DR
    case (cur_state)
      S_UPDATE_IR,
      S_RUN_TEST_IDLE : begin
        tck_pulse(0, 0); cur_state = S_RUN_TEST_IDLE;  // UPDATE_IR → RTI（若需要）
        tck_pulse(1, 0); cur_state = S_SELECT_DR;
        tck_pulse(0, 0); cur_state = S_CAPTURE_DR;
        tck_pulse(0, 0); cur_state = S_SHIFT_DR;
      end
      S_UPDATE_DR : begin
        tck_pulse(1, 0); cur_state = S_SELECT_DR;
        tck_pulse(0, 0); cur_state = S_CAPTURE_DR;
        tck_pulse(0, 0); cur_state = S_SHIFT_DR;
      end
      default: `uvm_error("SJTAG_DRV", $sformatf("shift_dr: 不支持从状态 %0s 出发", cur_state.name()))
    endcase

    // 移位（LSB first）
    for (int i = 0; i < dr_len - 1; i++) begin
      tck_pulse(0, dr_in[i]);
      dr_out[i] = vif.tdo;
    end
    // 最后一位，TMS=1 进入 EXIT1_DR
    tck_pulse(1, dr_in[dr_len-1]);
    dr_out[dr_len-1] = vif.tdo;
    cur_state = S_EXIT1_DR;

    // EXIT1_DR → UPDATE_DR
    tck_pulse(1, 0); cur_state = S_UPDATE_DR;
  endtask

  // ===========================================================================
  // 底层时序任务
  // ===========================================================================

  // 产生一个 TCK 脉冲，并在上升沿前设置 TMS/TDI
  // TDO 在上升沿后（即 tck=1 稳定后）采样
  task tck_pulse(logic tms_val, logic tdi_val);
    vif.tms = tms_val;
    vif.tdi = tdi_val;
    #(tck_half_period_ns * 1ns);
    vif.tck = 1;
    #(tck_half_period_ns * 1ns);
    vif.tck = 0;
  endtask

endclass : sjtag_driver
