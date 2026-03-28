// =============================================================================
// sjtag2apb_bridge.sv - SJTAG 转 APB 协议转换桥顶层模块
//
// 功能：
//   通过 JTAG 接口驱动 APB 总线进行读写操作，实现两种协议的转换。
//   支持三种 IR 指令：BYPASS、IDCODE、APB_ACCESS。
//
// 时钟域说明：
//   TCK 域  : TAP 状态机、IR 寄存器、DR 移位寄存器
//   PCLK 域 : APB 主状态机
//   CDC     : 使用 Toggle 同步器传递控制脉冲；数据在脉冲到达前已稳定（准静态）
//
// APB_ACCESS 操作流程：
//   写操作：
//     1. SHIFT_IR  : 移入 INSTR_APB_ACCESS (4'h2)
//     2. SHIFT_DR  : 移入 {1'b1, addr[31:0], wdata[31:0]}（LSB first）
//     3. UPDATE_DR : 桥自动发起 APB 写事务
//   读操作：
//     1. SHIFT_IR  : 移入 INSTR_APB_ACCESS (4'h2)
//     2. SHIFT_DR  : 移入 {1'b0, addr[31:0], 32'h0}（LSB first）
//     3. UPDATE_DR : 桥自动发起 APB 读事务
//     4. CAPTURE_DR: 读数据加载到 DR 移位寄存器的 DATA 域
//     5. SHIFT_DR  : 移出读数据（TDO 输出）
//
// DR 移位格式（APB_ACCESS，65bit，LSB first）：
//   [64]    = RW    (1=写，0=读)
//   [63:32] = PADDR
//   [31:0]  = DATA
//
// 端口：
//   JTAG 端口 : tck, trst_n, tms, tdi, tdo
//   APB  端口 : pclk, presetn, psel, penable, pwrite,
//               paddr, pwdata, prdata, pready, pslverr
// =============================================================================

module sjtag2apb_bridge
  import sjtag2apb_pkg::*;
#(
  parameter logic [31:0] DEVICE_IDCODE = IDCODE_VAL
)(
  // -------------------------------------------------------------------------
  // JTAG 端口
  // -------------------------------------------------------------------------
  input  logic                  tck,
  input  logic                  trst_n,
  input  logic                  tms,
  input  logic                  tdi,
  output logic                  tdo,

  // -------------------------------------------------------------------------
  // APB 主端口
  // -------------------------------------------------------------------------
  input  logic                  pclk,
  input  logic                  presetn,
  output logic                  psel,
  output logic                  penable,
  output logic                  pwrite,
  output logic [APB_ADDR_W-1:0] paddr,
  output logic [APB_DATA_W-1:0] pwdata,
  input  logic [APB_DATA_W-1:0] prdata,
  input  logic                  pready,
  input  logic                  pslverr
);

  // ===========================================================================
  // TAP 控制器实例
  // ===========================================================================
  tap_state_e tap_state;

  sjtag_tap_ctrl u_tap_ctrl (
    .tck      (tck),
    .trst_n   (trst_n),
    .tms      (tms),
    .tap_state(tap_state)
  );

  // ===========================================================================
  // IR 寄存器（TCK 时钟域）
  // ===========================================================================
  logic [IR_LEN-1:0] ir_shift_q;   // IR 移位寄存器
  logic [IR_LEN-1:0] ir_q;         // IR 并行寄存器（UPDATE_IR 时锁存）
  tap_instr_e        cur_instr;     // 当前生效指令

  always_ff @(posedge tck or negedge trst_n) begin : ir_reg
    if (!trst_n) begin
      ir_shift_q <= {IR_LEN{1'b1}};    // 复位为全 1（BYPASS）
      ir_q       <= INSTR_BYPASS;
    end else begin
      case (tap_state)
        // CAPTURE_IR：加载固定值（bit0=1，bit1=0，高位补 0），符合 IEEE 1149.1
        TAP_CAPTURE_IR : ir_shift_q <= {{(IR_LEN-2){1'b0}}, 2'b01};
        // SHIFT_IR：LSB first，TDI 从高位移入
        TAP_SHIFT_IR   : ir_shift_q <= {tdi, ir_shift_q[IR_LEN-1:1]};
        // UPDATE_IR：将移位寄存器值锁存到并行寄存器
        TAP_UPDATE_IR  : ir_q       <= ir_shift_q;
        default        : ;
      endcase
    end
  end : ir_reg

  assign cur_instr = tap_instr_e'(ir_q);

  // ===========================================================================
  // DR 移位寄存器（TCK 时钟域）
  // ===========================================================================

  // --------------------------------------------------------------------------
  // APB_ACCESS DR（65bit）
  // --------------------------------------------------------------------------
  logic [DR_APB_LEN-1:0] dr_apb_shift_q;  // 移位寄存器
  logic [DR_APB_LEN-1:0] dr_apb_q;        // 并行寄存器（UPDATE_DR 时锁存）

  // 来自 PCLK 域的 APB 读数据（已同步到 TCK 域）
  logic [APB_DATA_W-1:0] apb_rdata_tck;

  always_ff @(posedge tck or negedge trst_n) begin : dr_apb_reg
    if (!trst_n) begin
      dr_apb_shift_q <= '0;
      dr_apb_q       <= '0;
    end else if (cur_instr == INSTR_APB_ACCESS) begin
      case (tap_state)
        // CAPTURE_DR：RW/ADDR 保持，DATA 域更新为最新读数据
        TAP_CAPTURE_DR : dr_apb_shift_q <=
            {dr_apb_q[DR_APB_LEN-1 : APB_DATA_W], apb_rdata_tck};
        // SHIFT_DR：LSB first，TDI 从高位移入，bit0 输出到 TDO
        TAP_SHIFT_DR   : dr_apb_shift_q <=
            {tdi, dr_apb_shift_q[DR_APB_LEN-1:1]};
        // UPDATE_DR：锁存到并行寄存器，触发 APB 事务
        TAP_UPDATE_DR  : dr_apb_q <= dr_apb_shift_q;
        default        : ;
      endcase
    end
  end : dr_apb_reg

  // --------------------------------------------------------------------------
  // IDCODE DR（32bit，只读）
  // --------------------------------------------------------------------------
  logic [31:0] dr_idcode_shift_q;

  always_ff @(posedge tck or negedge trst_n) begin : dr_idcode_reg
    if (!trst_n) begin
      dr_idcode_shift_q <= DEVICE_IDCODE;
    end else if (cur_instr == INSTR_IDCODE) begin
      case (tap_state)
        TAP_CAPTURE_DR : dr_idcode_shift_q <= DEVICE_IDCODE;
        TAP_SHIFT_DR   : dr_idcode_shift_q <= {tdi, dr_idcode_shift_q[31:1]};
        default        : ;
      endcase
    end
  end : dr_idcode_reg

  // --------------------------------------------------------------------------
  // BYPASS DR（1bit）
  // --------------------------------------------------------------------------
  logic dr_bypass_q;

  always_ff @(posedge tck or negedge trst_n) begin : dr_bypass_reg
    if (!trst_n)                             dr_bypass_q <= 1'b0;
    else if (tap_state == TAP_CAPTURE_DR)    dr_bypass_q <= 1'b0;
    else if (tap_state == TAP_SHIFT_DR)      dr_bypass_q <= tdi;
  end : dr_bypass_reg

  // ===========================================================================
  // TDO 多路选择（TCK 下降沿更新，满足建立/保持时间要求）
  // ===========================================================================
  logic tdo_mux;

  always_comb begin : tdo_mux_logic
    case (cur_instr)
      INSTR_APB_ACCESS : tdo_mux = dr_apb_shift_q[0];
      INSTR_IDCODE     : tdo_mux = dr_idcode_shift_q[0];
      default          : tdo_mux = dr_bypass_q;          // BYPASS
    endcase
  end : tdo_mux_logic

  // TDO 在 TCK 下降沿更新（JTAG 规范要求，给主机提供足够的建立时间）
  always_ff @(negedge tck or negedge trst_n) begin : tdo_ff
    if (!trst_n) tdo <= 1'b1;
    else         tdo <= (tap_state == TAP_SHIFT_DR || tap_state == TAP_SHIFT_IR)
                        ? tdo_mux : 1'b1;
  end : tdo_ff

  // ===========================================================================
  // CDC：TCK 域 → PCLK 域（Toggle 同步器）
  // 传递 APB 事务启动信号（UPDATE_DR 脉冲）
  //
  // 原理：UPDATE_DR 每发生一次，toggle 信号翻转一次；
  //       PCLK 域通过 2FF 同步后检测边沿，产生单周期脉冲。
  // ===========================================================================

  // TCK 域：产生 toggle 信号
  logic apb_req_toggle_tck;

  always_ff @(posedge tck or negedge trst_n) begin : apb_req_toggle_gen
    if (!trst_n) apb_req_toggle_tck <= 1'b0;
    else if ((tap_state == TAP_UPDATE_DR) && (cur_instr == INSTR_APB_ACCESS))
      apb_req_toggle_tck <= ~apb_req_toggle_tck;
  end : apb_req_toggle_gen

  // PCLK 域：2FF 同步 + 边沿检测
  logic [1:0] apb_req_sync_ff;
  logic       apb_req_toggle_prev;
  logic       apb_start_pclk;       // APB 事务启动脉冲（PCLK 域，单周期）

  always_ff @(posedge pclk or negedge presetn) begin : apb_req_sync
    if (!presetn) begin
      apb_req_sync_ff      <= 2'b00;
      apb_req_toggle_prev  <= 1'b0;
    end else begin
      apb_req_sync_ff     <= {apb_req_sync_ff[0], apb_req_toggle_tck};
      apb_req_toggle_prev <= apb_req_sync_ff[1];
    end
  end : apb_req_sync

  assign apb_start_pclk = apb_req_sync_ff[1] ^ apb_req_toggle_prev;

  // ===========================================================================
  // APB 主状态机（PCLK 时钟域）
  //
  // 标准 APB 协议时序：
  //   IDLE  : PSEL=0，PENABLE=0
  //   SETUP : PSEL=1，PENABLE=0（持续 1 个 PCLK 周期）
  //   ACCESS: PSEL=1，PENABLE=1（等待 PREADY=1 完成）
  // ===========================================================================

  typedef enum logic [1:0] {
    APB_IDLE   = 2'b00,
    APB_SETUP  = 2'b01,
    APB_ACCESS = 2'b10
  } apb_state_e;

  apb_state_e            apb_state_q;
  logic [APB_DATA_W-1:0] apb_rdata_q;    // 读数据寄存器（PCLK 域）
  logic                  apb_done_pclk;  // APB 完成脉冲（PCLK 域，单周期）

  always_ff @(posedge pclk or negedge presetn) begin : apb_master_fsm
    if (!presetn) begin
      apb_state_q  <= APB_IDLE;
      psel         <= 1'b0;
      penable      <= 1'b0;
      pwrite       <= 1'b0;
      paddr        <= '0;
      pwdata       <= '0;
      apb_rdata_q  <= '0;
      apb_done_pclk <= 1'b0;
    end else begin
      apb_done_pclk <= 1'b0;   // 默认低，仅完成时拉高一个周期

      case (apb_state_q)

        APB_IDLE: begin
          if (apb_start_pclk) begin
            // 从 dr_apb_q（TCK 域准静态信号）读取事务参数
            // 此时 dr_apb_q 已在 UPDATE_DR 时锁存并稳定，
            // Toggle 同步器引入的 2 PCLK 延迟确保数据有效
            pwrite      <= dr_apb_q[DR_APB_LEN-1];
            paddr       <= dr_apb_q[APB_ADDR_W + APB_DATA_W - 1 : APB_DATA_W];
            pwdata      <= dr_apb_q[APB_DATA_W-1 : 0];
            psel        <= 1'b1;
            penable     <= 1'b0;
            apb_state_q <= APB_SETUP;
          end
        end

        APB_SETUP: begin
          // SETUP 阶段持续 1 个 PCLK，随后进入 ACCESS
          penable     <= 1'b1;
          apb_state_q <= APB_ACCESS;
        end

        APB_ACCESS: begin
          if (pready) begin
            // APB 从设备就绪，完成事务
            psel        <= 1'b0;
            penable     <= 1'b0;
            if (!pwrite) begin
              apb_rdata_q <= prdata;    // 读操作：保存读回数据
            end
            apb_done_pclk <= 1'b1;
            apb_state_q   <= APB_IDLE;
          end
          // pslverr 不影响状态机，由上层软件通过下次读 DR 判断结果
        end

        default: apb_state_q <= APB_IDLE;

      endcase
    end
  end : apb_master_fsm

  // ===========================================================================
  // CDC：PCLK 域 → TCK 域（Toggle 同步器 + 数据同步）
  // 传递 APB 读数据及完成标志回 TCK 域
  //
  // apb_rdata_q 在 apb_done_pclk 后保持稳定；
  // 2FF 同步读数据（多 bit 准静态 CDC），TCK << PCLK 时数据充分稳定。
  // ===========================================================================

  // PCLK 域：done 信号产生 toggle
  logic apb_done_toggle_pclk;

  always_ff @(posedge pclk or negedge presetn) begin : apb_done_toggle_gen
    if (!presetn) apb_done_toggle_pclk <= 1'b0;
    else if (apb_done_pclk) apb_done_toggle_pclk <= ~apb_done_toggle_pclk;
  end : apb_done_toggle_gen

  // TCK 域：同步 done toggle（不使用，预留给未来握手扩展）
  // 读数据直接 2FF 同步到 TCK 域（准静态，CAPTURE_DR 时已充分稳定）
  logic [APB_DATA_W-1:0] apb_rdata_sync_0;  // 第一级同步器

  always_ff @(posedge tck or negedge trst_n) begin : apb_rdata_sync
    if (!trst_n) begin
      apb_rdata_sync_0 <= '0;
      apb_rdata_tck    <= '0;
    end else begin
      apb_rdata_sync_0 <= apb_rdata_q;
      apb_rdata_tck    <= apb_rdata_sync_0;
    end
  end : apb_rdata_sync

endmodule : sjtag2apb_bridge
