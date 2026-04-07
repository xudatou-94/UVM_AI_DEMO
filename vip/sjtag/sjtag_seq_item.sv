// =============================================================================
// sjtag_seq_item.sv - SJTAG 事务对象
//
// 描述一次完整的 SJTAG 操作，支持以下操作类型：
//   SJTAG_RESET      - TAP 复位（TRST_N 或 5xTMS=1）
//   SJTAG_APB_WRITE  - 通过 JTAG 向 APB 地址写数据
//   SJTAG_APB_READ   - 通过 JTAG 从 APB 地址读数据
//   SJTAG_IDCODE     - 读取设备 IDCODE
// =============================================================================

class sjtag_seq_item extends uvm_sequence_item;
  `uvm_object_utils(sjtag_seq_item)

  // -------------------------------------------------------------------------
  // 操作类型枚举
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    SJTAG_RESET     = 2'h0,
    SJTAG_APB_WRITE = 2'h1,
    SJTAG_APB_READ  = 2'h2,
    SJTAG_IDCODE    = 2'h3
  } sjtag_op_e;

  // -------------------------------------------------------------------------
  // 事务字段
  // -------------------------------------------------------------------------
  rand sjtag_op_e       op;           // 操作类型
  rand logic [31:0]     addr;         // APB 地址（APB_WRITE/READ 时有效）
  rand logic [31:0]     wdata;        // 写数据（APB_WRITE 时有效）
       logic [31:0]     rdata;        // 读数据（APB_READ/IDCODE 时由 driver 填入）
       logic            slverr;       // APB 从设备错误标志（预留）

  // -------------------------------------------------------------------------
  // 约束
  // -------------------------------------------------------------------------
  // 地址 4 字节对齐
  constraint c_addr_align { addr[1:0] == 2'b00; }

  // -------------------------------------------------------------------------
  // 方法
  // -------------------------------------------------------------------------
  function new(string name = "sjtag_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("op=%-12s addr=0x%08x wdata=0x%08x rdata=0x%08x",
                     op.name(), addr, wdata, rdata);
  endfunction

  function void do_copy(uvm_object rhs);
    sjtag_seq_item rhs_;
    super.do_copy(rhs);
    if (!$cast(rhs_, rhs)) return;
    op     = rhs_.op;
    addr   = rhs_.addr;
    wdata  = rhs_.wdata;
    rdata  = rhs_.rdata;
    slverr = rhs_.slverr;
  endfunction

  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    sjtag_seq_item rhs_;
    if (!$cast(rhs_, rhs)) return 0;
    return (op == rhs_.op) && (addr == rhs_.addr) &&
           (wdata == rhs_.wdata);
  endfunction

endclass : sjtag_seq_item
