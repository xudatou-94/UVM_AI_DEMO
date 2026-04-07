// =============================================================================
// apb_seq_item.sv - APB 事务对象
//
// 描述一次完整的 APB 读或写事务，包含 APB4 扩展字段（PPROT/PSTRB）。
// rdata / pslverr 为非 rand（由 driver 或 monitor 填入）。
// =============================================================================

class apb_seq_item extends uvm_sequence_item;
  `uvm_object_utils(apb_seq_item)

  // -------------------------------------------------------------------------
  // 事务字段
  // -------------------------------------------------------------------------
  rand logic [31:0]  addr;      // PADDR
  rand logic         rw;        // 1=写，0=读
  rand logic [31:0]  wdata;     // PWDATA（写操作时有效）
       logic [31:0]  rdata;     // PRDATA（读操作时由 driver/monitor 填入）
       logic         pslverr;   // PSLVERR（由 slave/monitor 填入）

  // APB4 扩展字段
  rand logic [2:0]   pprot;     // PPROT：[0]=privileged, [1]=secure, [2]=instruction
  rand logic [3:0]   pstrb;     // PSTRB：写字节使能（写操作时有效）

  // 等待状态数（slave 插入 wait state 的周期数，用于 slave driver 配置）
  rand int unsigned  wait_states;

  // -------------------------------------------------------------------------
  // 约束
  // -------------------------------------------------------------------------
  // 地址 4 字节对齐
  constraint c_addr_align    { addr[1:0] == 2'b00; }
  // 默认无保护属性
  constraint c_pprot_default { pprot == 3'b000; }
  // 写时默认全字节使能；读时 PSTRB 无意义
  constraint c_pstrb_default { if (rw) pstrb == 4'hF; else pstrb == 4'h0; }
  // 等待状态限制（防止仿真卡死）
  constraint c_wait_states   { wait_states inside {[0:7]}; }

  // -------------------------------------------------------------------------
  // 方法
  // -------------------------------------------------------------------------
  function new(string name = "apb_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%-5s addr=0x%08x wdata=0x%08x rdata=0x%08x pslverr=%0b wait=%0d",
                     rw ? "WRITE" : "READ", addr, wdata, rdata, pslverr, wait_states);
  endfunction

  function void do_copy(uvm_object rhs);
    apb_seq_item rhs_;
    super.do_copy(rhs);
    if (!$cast(rhs_, rhs)) return;
    addr        = rhs_.addr;
    rw          = rhs_.rw;
    wdata       = rhs_.wdata;
    rdata       = rhs_.rdata;
    pslverr     = rhs_.pslverr;
    pprot       = rhs_.pprot;
    pstrb       = rhs_.pstrb;
    wait_states = rhs_.wait_states;
  endfunction

  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    apb_seq_item rhs_;
    if (!$cast(rhs_, rhs)) return 0;
    return (addr == rhs_.addr) && (rw == rhs_.rw) &&
           (rw ? (wdata == rhs_.wdata) : (rdata == rhs_.rdata));
  endfunction

endclass : apb_seq_item
