// =============================================================================
// sjtag2apb_coverage.sv - sjtag2apb 功能覆盖率收集器
//
// 描述：
//   订阅 SJTAG agent 和 APB agent 的 analysis port，对关键功能点进行覆盖率采样。
//   包含以下覆盖组：
//     - cg_sjtag_op      : SJTAG 操作类型覆盖
//     - cg_apb_rw        : APB 读写方向覆盖
//     - cg_apb_wait      : APB 等待状态覆盖（零/低/高）
//     - cg_apb_pslverr   : APB 从设备错误覆盖
//     - cg_apb_addr_range: APB 地址范围覆盖（低/中/高地址空间）
//
// 连接方式：
//   env.connect_phase 中：
//     sjtag_agt.ap.connect(coverage.sjtag_export)
//     apb_agt.ap.connect(coverage.apb_export)
// =============================================================================

class sjtag2apb_coverage extends uvm_subscriber #(apb_seq_item);
  `uvm_component_utils(sjtag2apb_coverage)

  // --------------------------------------------------------------------------
  // analysis import 声明宏（为两个不同类型定义各自的 _decl）
  // --------------------------------------------------------------------------
  `uvm_analysis_imp_decl(_sjtag)
  `uvm_analysis_imp_decl(_apb)

  // SJTAG 事务的 analysis import
  uvm_analysis_imp_sjtag #(sjtag_seq_item, sjtag2apb_coverage) sjtag_export;
  // APB 事务的 analysis import
  uvm_analysis_imp_apb   #(apb_seq_item,   sjtag2apb_coverage) apb_export;

  // --------------------------------------------------------------------------
  // 采样用临时变量（由 write 函数设置，覆盖组采样）
  // --------------------------------------------------------------------------
  sjtag_seq_item sjtag_item_sample;
  apb_seq_item   apb_item_sample;

  // --------------------------------------------------------------------------
  // 覆盖组：SJTAG 操作类型
  // 覆盖所有四种 JTAG 操作：复位、APB 写、APB 读、IDCODE 读取
  // --------------------------------------------------------------------------
  covergroup cg_sjtag_op;
    cp_op : coverpoint sjtag_item_sample.op {
      bins reset     = {sjtag_seq_item::SJTAG_RESET};
      bins apb_write = {sjtag_seq_item::SJTAG_APB_WRITE};
      bins apb_read  = {sjtag_seq_item::SJTAG_APB_READ};
      bins idcode    = {sjtag_seq_item::SJTAG_IDCODE};
    }
  endgroup

  // --------------------------------------------------------------------------
  // 覆盖组：APB 读写方向
  // rw=0 表示读，rw=1 表示写
  // --------------------------------------------------------------------------
  covergroup cg_apb_rw;
    cp_rw : coverpoint apb_item_sample.rw {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
  endgroup

  // --------------------------------------------------------------------------
  // 覆盖组：APB 等待状态分段覆盖
  // 分为三档：零等待、低等待（1-3 周期）、高等待（4-7 周期）
  // --------------------------------------------------------------------------
  covergroup cg_apb_wait;
    cp_wait : coverpoint apb_item_sample.wait_states {
      bins zero = {0};
      bins low  = {[1:3]};
      bins high = {[4:7]};
    }
  endgroup

  // --------------------------------------------------------------------------
  // 覆盖组：APB 从设备错误（PSLVERR）
  // 覆盖正常响应和错误响应两种情况
  // --------------------------------------------------------------------------
  covergroup cg_apb_pslverr;
    cp_pslverr : coverpoint apb_item_sample.pslverr {
      bins no_error = {1'b0};
      bins error    = {1'b1};
    }
  endgroup

  // --------------------------------------------------------------------------
  // 覆盖组：APB 地址范围覆盖（按高 16 位分段）
  // 覆盖零地址区、中间地址区、高地址区（0xFF00_xxxx 及以上）
  // --------------------------------------------------------------------------
  covergroup cg_apb_addr_range;
    cp_addr : coverpoint apb_item_sample.addr[31:16] {
      // 零地址区：高 16 位为 0（低 64KB 空间）
      bins zero = {16'h0000};
      // 高地址区：高 16 位 >= 0xFF00（高端地址空间）
      bins high = {[16'hFF00 : 16'hFFFF]};
      // 中间地址区：其余所有地址
      bins mid  = default;
    }
  endgroup

  // --------------------------------------------------------------------------
  // 构造函数：初始化覆盖组
  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    // 构造函数中实例化覆盖组
    cg_sjtag_op      = new();
    cg_apb_rw        = new();
    cg_apb_wait      = new();
    cg_apb_pslverr   = new();
    cg_apb_addr_range = new();
  endfunction

  // --------------------------------------------------------------------------
  // build_phase：创建 analysis exports
  // --------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sjtag_export = new("sjtag_export", this);
    apb_export   = new("apb_export",   this);
  endfunction

  // --------------------------------------------------------------------------
  // write_sjtag：SJTAG monitor 回调
  // 每收到一笔 SJTAG 事务即采样 SJTAG 相关覆盖组
  // --------------------------------------------------------------------------
  function void write_sjtag(sjtag_seq_item item);
    sjtag_item_sample = item;
    cg_sjtag_op.sample();
    `uvm_info("COVERAGE",
              $sformatf("SJTAG 覆盖采样：op=%s", item.op.name()),
              UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // write_apb：APB monitor 回调
  // 每收到一笔 APB 事务即采样 APB 相关覆盖组
  // --------------------------------------------------------------------------
  function void write_apb(apb_seq_item item);
    apb_item_sample = item;
    cg_apb_rw.sample();
    cg_apb_wait.sample();
    cg_apb_pslverr.sample();
    cg_apb_addr_range.sample();
    `uvm_info("COVERAGE",
              $sformatf("APB 覆盖采样：rw=%0b addr=0x%08x wait=%0d pslverr=%0b",
                        item.rw, item.addr, item.wait_states, item.pslverr),
              UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // write：uvm_subscriber 基类要求实现，转发到 write_apb
  // （apb_export 已通过 `uvm_analysis_imp_decl 独立声明，此函数为兼容基类）
  // --------------------------------------------------------------------------
  function void write(apb_seq_item t);
    write_apb(t);
  endfunction

endclass : sjtag2apb_coverage
