// =============================================================================
// sjtag2apb_scoreboard.sv - sjtag2apb 验证记分板
//
// 描述：
//   订阅 APB monitor 的 analysis port，对所有 APB 事务进行行为检查。
//   维护影子存储器（shadow memory）跟踪写操作，对读操作验证返回数据正确性。
//   统计通过/失败次数，在 report_phase 打印汇总报告。
//
// 连接方式：
//   env.connect_phase 中：apb_agt.ap.connect(scoreboard.apb_export)
// =============================================================================

class sjtag2apb_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(sjtag2apb_scoreboard)

  // --------------------------------------------------------------------------
  // analysis import：接收来自 APB monitor 的事务
  // --------------------------------------------------------------------------
  `uvm_analysis_imp_decl(_apb)
  uvm_analysis_imp_apb #(apb_seq_item, sjtag2apb_scoreboard) apb_export;

  // --------------------------------------------------------------------------
  // 影子存储器：镜像 APB 写操作，用于读操作校验
  // --------------------------------------------------------------------------
  logic [31:0] shadow[logic [31:0]];

  // --------------------------------------------------------------------------
  // 统计计数器
  // --------------------------------------------------------------------------
  int pass_cnt;   // 通过次数
  int fail_cnt;   // 失败次数

  // --------------------------------------------------------------------------
  // 构造函数
  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // --------------------------------------------------------------------------
  // build_phase：创建 analysis export
  // --------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_export = new("apb_export", this);
    pass_cnt   = 0;
    fail_cnt   = 0;
  endfunction

  // --------------------------------------------------------------------------
  // write_apb：APB monitor 回调函数
  // 每当 monitor 完成一笔事务即调用此函数
  // --------------------------------------------------------------------------
  function void write_apb(apb_seq_item item);
    logic [31:0] expected_data;

    if (item.rw) begin
      // -----------------------------------------------------------------------
      // 写事务：更新影子存储器，记录本次写入值
      // -----------------------------------------------------------------------
      shadow[item.addr] = item.wdata;
      `uvm_info("SCOREBOARD",
                $sformatf("APB 写记录：addr=0x%08x wdata=0x%08x",
                          item.addr, item.wdata),
                UVM_MEDIUM)
    end
    else begin
      // -----------------------------------------------------------------------
      // 读事务：与影子存储器中的期望值比对
      // -----------------------------------------------------------------------
      if (shadow.exists(item.addr)) begin
        expected_data = shadow[item.addr];

        if (item.rdata === expected_data) begin
          // 数据匹配，记为通过
          pass_cnt++;
          `uvm_info("SCOREBOARD",
                    $sformatf("PASS：APB 读 addr=0x%08x rdata=0x%08x（期望=0x%08x）",
                              item.addr, item.rdata, expected_data),
                    UVM_MEDIUM)
        end
        else begin
          // 数据不匹配，记为失败并报告错误
          fail_cnt++;
          `uvm_error("SCOREBOARD",
                     $sformatf("FAIL：APB 读数据不匹配 addr=0x%08x rdata=0x%08x 期望=0x%08x",
                               item.addr, item.rdata, expected_data))
        end

      end
      else begin
        // 影子存储器中不存在该地址的写记录，仅记录不做强制校验
        // 首次读取未预置地址为正常场景（slave 返回 0xDEAD_BEEF）
        `uvm_info("SCOREBOARD",
                  $sformatf("APB 读（地址未在影子存储器中）：addr=0x%08x rdata=0x%08x",
                            item.addr, item.rdata),
                  UVM_LOW)
      end
    end
  endfunction

  // --------------------------------------------------------------------------
  // report_phase：打印最终通过/失败汇总
  // --------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    string result_str;

    // 根据失败次数决定整体结果
    if (fail_cnt == 0) begin
      result_str = "*** SCOREBOARD PASS ***";
    end
    else begin
      result_str = "*** SCOREBOARD FAIL ***";
    end

    `uvm_info("SCOREBOARD",
              $sformatf("\n%s\n  通过次数（PASS）：%0d\n  失败次数（FAIL）：%0d\n",
                        result_str, pass_cnt, fail_cnt),
              UVM_NONE)

    // 若存在失败，再次以 uvm_error 形式报告，确保仿真工具统计到错误
    if (fail_cnt > 0) begin
      `uvm_error("SCOREBOARD",
                 $sformatf("仿真结束：共 %0d 笔校验失败", fail_cnt))
    end
  endfunction

endclass : sjtag2apb_scoreboard
