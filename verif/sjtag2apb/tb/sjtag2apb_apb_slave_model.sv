// =============================================================================
// sjtag2apb_apb_slave_model.sv - APB 从设备仿真模型
//
// 描述：
//   直接驱动 APB 接口信号的 UVM component，不依赖 APB VIP slave driver。
//   支持内存读写、可配置等待状态、PSLVERR 注入。
//   从 config_db 获取接口句柄及配置参数，自主响应 APB 总线事务。
//
// 使用方式：
//   在 env 的 build_phase 中通过 config_db 设置 "apb_vif"、
//   "default_wait_states"、"default_pslverr" 等参数。
// =============================================================================

class sjtag2apb_apb_slave_model extends uvm_component;
  `uvm_component_utils(sjtag2apb_apb_slave_model)

  // --------------------------------------------------------------------------
  // 虚接口句柄（从 config_db 获取）
  // --------------------------------------------------------------------------
  virtual apb_if vif;

  // --------------------------------------------------------------------------
  // 内部存储器：关联数组，地址映射到 32 位数据
  // --------------------------------------------------------------------------
  logic [31:0] mem[logic [31:0]];

  // --------------------------------------------------------------------------
  // 配置字段
  // --------------------------------------------------------------------------
  // 每次事务插入的默认等待状态周期数
  int unsigned default_wait_states = 0;
  // 默认 PSLVERR 响应（0=正常，1=返回错误）
  bit          default_pslverr     = 0;

  // --------------------------------------------------------------------------
  // 错误注入：特定地址返回 PSLVERR
  // pslverr_addrs[addr] 存在则该地址事务返回 PSLVERR=1
  // --------------------------------------------------------------------------
  bit pslverr_addrs[logic [31:0]];

  // --------------------------------------------------------------------------
  // 构造函数
  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // --------------------------------------------------------------------------
  // build_phase：从 config_db 获取接口及配置参数
  // --------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 获取 APB 虚接口
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "apb_vif", vif)) begin
      `uvm_fatal("SLAVE_MODEL", "未能从 config_db 获取 apb_vif，请检查 tb_top 设置")
    end

    // 获取可选配置参数（若未设置则使用默认值）
    void'(uvm_config_db #(int unsigned)::get(this, "", "default_wait_states",
                                              default_wait_states));
    void'(uvm_config_db #(bit)::get(this, "", "default_pslverr",
                                    default_pslverr));

    `uvm_info("SLAVE_MODEL",
              $sformatf("配置：default_wait_states=%0d default_pslverr=%0b",
                        default_wait_states, default_pslverr),
              UVM_MEDIUM)
  endfunction

  // --------------------------------------------------------------------------
  // 预加载方法：将指定地址的初始值写入内部存储器
  // 可在测试开始前调用，模拟 ROM 内容或预置寄存器值
  // --------------------------------------------------------------------------
  function void preload(logic [31:0] addr, logic [31:0] data);
    mem[addr] = data;
    `uvm_info("SLAVE_MODEL",
              $sformatf("预加载 mem[0x%08x] = 0x%08x", addr, data),
              UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // run_phase：APB 从设备主状态机
  // --------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    logic [31:0] trans_addr;
    logic [31:0] trans_wdata;
    logic        trans_write;
    logic        trans_pslverr;
    int unsigned wait_cnt;

    // 初始化总线输出信号
    vif.PRDATA  = '0;
    vif.PREADY  = 1'b1;   // 默认 PREADY=1，表示无等待
    vif.PSLVERR = 1'b0;

    // 等待 PRESETn 上升沿（复位释放），确保初始化完成后再处理事务
    @(posedge vif.PRESETn);
    `uvm_info("SLAVE_MODEL", "PRESETn 已释放，开始监听 APB 事务", UVM_MEDIUM)

    forever begin
      // 等待 PCLK 上升沿，检测 SETUP 阶段
      // SETUP 阶段特征：PSEL=1 且 PENABLE=0
      @(posedge vif.PCLK);

      if (vif.PSEL && !vif.PENABLE) begin
        // ----------------------------------------------------------------
        // 检测到 SETUP 阶段，锁存地址和控制信号
        // ----------------------------------------------------------------
        trans_addr  = vif.PADDR;
        trans_wdata = vif.PWDATA;
        trans_write = vif.PWRITE;

        // 等待下一个时钟上升沿，进入 ACCESS 阶段（PENABLE=1）
        @(posedge vif.PCLK);

        // ----------------------------------------------------------------
        // 插入等待状态：驱动 PREADY=0 若干周期
        // ----------------------------------------------------------------
        if (default_wait_states > 0) begin
          vif.PREADY = 1'b0;
          // 循环插入等待状态周期
          for (wait_cnt = 0; wait_cnt < default_wait_states; wait_cnt++) begin
            @(posedge vif.PCLK);
          end
        end

        // PREADY 拉高，表示本拍完成事务
        vif.PREADY = 1'b1;

        // ----------------------------------------------------------------
        // 处理写操作：将数据写入内部存储器
        // ----------------------------------------------------------------
        if (trans_write) begin
          mem[trans_addr] = trans_wdata;
          `uvm_info("SLAVE_MODEL",
                    $sformatf("APB 写：addr=0x%08x data=0x%08x",
                              trans_addr, trans_wdata),
                    UVM_HIGH)
        end
        // ----------------------------------------------------------------
        // 处理读操作：从内部存储器读取数据，未初始化地址返回特征值
        // ----------------------------------------------------------------
        else begin
          if (mem.exists(trans_addr)) begin
            vif.PRDATA = mem[trans_addr];
          end
          else begin
            // 未初始化地址返回 0xDEAD_BEEF，便于调试识别
            vif.PRDATA = 32'hDEAD_BEEF;
          end
          `uvm_info("SLAVE_MODEL",
                    $sformatf("APB 读：addr=0x%08x rdata=0x%08x",
                              trans_addr, vif.PRDATA),
                    UVM_HIGH)
        end

        // ----------------------------------------------------------------
        // PSLVERR 处理：检查该地址是否在错误注入列表中
        // ----------------------------------------------------------------
        if (pslverr_addrs.exists(trans_addr)) begin
          // 该地址被标记为需要返回从设备错误
          vif.PSLVERR = 1'b1;
          `uvm_info("SLAVE_MODEL",
                    $sformatf("注入 PSLVERR：addr=0x%08x", trans_addr),
                    UVM_MEDIUM)
        end
        else begin
          vif.PSLVERR = default_pslverr;
        end

        // 等待一个时钟，确保信号被采样后再复位
        @(posedge vif.PCLK);

        // ----------------------------------------------------------------
        // 事务结束：复位 PREADY 和 PSLVERR 到默认状态
        // ----------------------------------------------------------------
        vif.PREADY  = 1'b1;
        vif.PSLVERR = 1'b0;

      end // if SETUP phase
    end // forever
  endtask

endclass : sjtag2apb_apb_slave_model
