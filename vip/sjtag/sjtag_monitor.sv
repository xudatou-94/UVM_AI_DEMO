// =============================================================================
// sjtag_monitor.sv - SJTAG Monitor
//
// 功能：
//   被动监听 JTAG 引脚时序，重建 TAP 状态机并还原完整的 IR/DR 事务，
//   通过 analysis_port 广播 sjtag_seq_item 给 scoreboard / coverage。
//
// 采样策略：
//   TMS/TDI 在 TCK 上升沿采样（建立时间由 driver 保证）
//   TDO    在 TCK 上升沿采样（DUT 在下降沿更新，上升沿稳定）
// =============================================================================

class sjtag_monitor extends uvm_monitor;
  `uvm_component_utils(sjtag_monitor)

  // -------------------------------------------------------------------------
  // 端口 & 接口
  // -------------------------------------------------------------------------
  uvm_analysis_port #(sjtag_seq_item) ap;
  virtual sjtag_if vif;

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
  } mon_tap_state_e;

  mon_tap_state_e cur_state;

  // 已锁定的 IR 值（UPDATE_IR 后更新）
  logic [3:0] current_ir;

  // DR 移位寄存器（最大支持 65bit）
  logic [64:0] dr_shift;
  int unsigned dr_bit_cnt;

  // IR 移位寄存器（最大 4bit）
  logic [3:0]  ir_shift;
  int unsigned ir_bit_cnt;

  // -------------------------------------------------------------------------
  // 构造函数 & build_phase
  // -------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual sjtag_if)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "sjtag_monitor: 未获取到 virtual sjtag_if")
  endfunction

  // -------------------------------------------------------------------------
  // run_phase：等待复位释放后开始采样
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    // 等待 trst_n 释放
    @(posedge vif.trst_n);
    cur_state  = S_TEST_LOGIC_RESET;
    current_ir = 4'hF;  // BYPASS 为复位后默认 IR

    forever begin
      @(posedge vif.tck);
      // trst_n 异步复位优先
      if (!vif.trst_n) begin
        cur_state  = S_TEST_LOGIC_RESET;
        current_ir = 4'hF;
        continue;
      end
      sample_tap(vif.tms, vif.tdi, vif.tdo);
    end
  endtask

  // -------------------------------------------------------------------------
  // TAP 状态机转移 + 数据采集
  // -------------------------------------------------------------------------
  task sample_tap(logic tms, logic tdi, logic tdo);
    mon_tap_state_e next_state;

    // 计算下一状态（标准 IEEE 1149.1 转移表）
    case (cur_state)
      S_TEST_LOGIC_RESET : next_state = tms ? S_TEST_LOGIC_RESET : S_RUN_TEST_IDLE;
      S_RUN_TEST_IDLE    : next_state = tms ? S_SELECT_DR        : S_RUN_TEST_IDLE;
      S_SELECT_DR        : next_state = tms ? S_SELECT_IR        : S_CAPTURE_DR;
      S_CAPTURE_DR       : next_state = tms ? S_EXIT1_DR         : S_SHIFT_DR;
      S_SHIFT_DR         : next_state = tms ? S_EXIT1_DR         : S_SHIFT_DR;
      S_EXIT1_DR         : next_state = tms ? S_UPDATE_DR        : S_PAUSE_DR;
      S_PAUSE_DR         : next_state = tms ? S_EXIT2_DR         : S_PAUSE_DR;
      S_EXIT2_DR         : next_state = tms ? S_UPDATE_DR        : S_SHIFT_DR;
      S_UPDATE_DR        : next_state = tms ? S_SELECT_DR        : S_RUN_TEST_IDLE;
      S_SELECT_IR        : next_state = tms ? S_TEST_LOGIC_RESET : S_CAPTURE_IR;
      S_CAPTURE_IR       : next_state = tms ? S_EXIT1_IR         : S_SHIFT_IR;
      S_SHIFT_IR         : next_state = tms ? S_EXIT1_IR         : S_SHIFT_IR;
      S_EXIT1_IR         : next_state = tms ? S_UPDATE_IR        : S_PAUSE_IR;
      S_PAUSE_IR         : next_state = tms ? S_EXIT2_IR         : S_PAUSE_IR;
      S_EXIT2_IR         : next_state = tms ? S_UPDATE_IR        : S_SHIFT_IR;
      S_UPDATE_IR        : next_state = tms ? S_SELECT_DR        : S_RUN_TEST_IDLE;
      default            : next_state = S_TEST_LOGIC_RESET;
    endcase

    // 进入新状态时的动作
    case (next_state)
      S_CAPTURE_IR : begin
        ir_shift   = '0;
        ir_bit_cnt = 0;
      end
      S_CAPTURE_DR : begin
        dr_shift   = '0;
        dr_bit_cnt = 0;
      end
      S_SHIFT_IR : begin
        // LSB first：TDI 移入 MSB 端，逐位右移
        ir_shift = {tdi, ir_shift[3:1]};
        ir_bit_cnt++;
      end
      S_SHIFT_DR : begin
        dr_shift = {tdi, dr_shift[64:1]};
        dr_bit_cnt++;
        // 同步记录 TDO（DR 移出值）
        // TDO 在此时钟沿已稳定
      end
      S_UPDATE_IR : begin
        // 最后一位在 EXIT1_IR 时已移入，连同本次 IR 锁定
        current_ir = ir_shift[3:0];
        `uvm_info("SJTAG_MON", $sformatf("UPDATE_IR: ir=4'h%0x cnt=%0d",
                  current_ir, ir_bit_cnt), UVM_HIGH)
      end
      S_UPDATE_DR : begin
        // DR 事务完成，根据当前 IR 构建 seq_item
        decode_dr_transaction();
      end
      default : ;
    endcase

    cur_state = next_state;
  endtask

  // -------------------------------------------------------------------------
  // 根据 IR 解码 DR 事务并广播
  // -------------------------------------------------------------------------
  task decode_dr_transaction();
    sjtag_seq_item item;

    case (current_ir)
      4'h1 : begin  // INSTR_IDCODE
        if (dr_bit_cnt >= 32) begin
          item = sjtag_seq_item::type_id::create("mon_item");
          item.op    = sjtag_seq_item::SJTAG_IDCODE;
          item.rdata = dr_shift[31:0];
          `uvm_info("SJTAG_MON",
                    $sformatf("IDCODE detected: 0x%08x", item.rdata), UVM_MEDIUM)
          ap.write(item);
        end
      end

      4'h2 : begin  // INSTR_APB_ACCESS
        if (dr_bit_cnt >= 65) begin
          item = sjtag_seq_item::type_id::create("mon_item");
          // DR 格式（LSB first 移入）：[64]=rw, [63:32]=addr, [31:0]=data
          // 经过移位寄存器后 dr_shift[64:0] 已按顺序还原
          if (dr_shift[64]) begin  // RW=1：写操作
            item.op    = sjtag_seq_item::SJTAG_APB_WRITE;
            item.addr  = dr_shift[63:32];
            item.wdata = dr_shift[31:0];
          end else begin           // RW=0：读操作
            item.op    = sjtag_seq_item::SJTAG_APB_READ;
            item.addr  = dr_shift[63:32];
            item.rdata = dr_shift[31:0];
          end
          `uvm_info("SJTAG_MON", $sformatf("APB_ACCESS: %s", item.convert2string()), UVM_MEDIUM)
          ap.write(item);
        end
      end

      4'hF : begin  // INSTR_BYPASS
        // 1bit BYPASS，忽略
      end

      default : begin
        `uvm_warning("SJTAG_MON", $sformatf("未知 IR=4'h%0x，忽略 DR 事务", current_ir))
      end
    endcase
  endtask

endclass : sjtag_monitor
