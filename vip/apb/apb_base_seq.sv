// =============================================================================
// apb_base_seq.sv - APB 基础 Sequence
//
// 提供 master 侧和 slave 侧的常用原子操作任务。
// Master sequence 继承本类后直接调用 write/read 任务；
// Slave sequence 继承后实现 respond 循环。
// =============================================================================

class apb_base_seq extends uvm_sequence #(apb_seq_item);
  `uvm_object_utils(apb_base_seq)

  function new(string name = "apb_base_seq");
    super.new(name);
  endfunction

  // -------------------------------------------------------------------------
  // Master 原子操作：写
  // -------------------------------------------------------------------------
  task write(logic [31:0] addr, logic [31:0] data,
             logic [2:0] pprot = 3'b000, logic [3:0] pstrb = 4'hF);
    apb_seq_item item;
    item = apb_seq_item::type_id::create("item");
    item.addr  = addr;
    item.rw    = 1;
    item.wdata = data;
    item.pprot = pprot;
    item.pstrb = pstrb;
    start_item(item);
    finish_item(item);
    if (item.pslverr)
      `uvm_warning("APB_SEQ", $sformatf("PSLVERR: WRITE addr=0x%08x", addr))
  endtask

  // -------------------------------------------------------------------------
  // Master 原子操作：读
  // -------------------------------------------------------------------------
  task read(logic [31:0] addr, output logic [31:0] rdata,
            input logic [2:0] pprot = 3'b000);
    apb_seq_item item;
    item = apb_seq_item::type_id::create("item");
    item.addr  = addr;
    item.rw    = 0;
    item.pprot = pprot;
    start_item(item);
    finish_item(item);
    rdata = item.rdata;
    if (item.pslverr)
      `uvm_warning("APB_SEQ", $sformatf("PSLVERR: READ addr=0x%08x", addr))
  endtask

  // -------------------------------------------------------------------------
  // Master 操作：读后核验（读回值与期望值比较）
  // -------------------------------------------------------------------------
  task read_check(logic [31:0] addr, logic [31:0] exp_data,
                  logic [31:0] mask = 32'hFFFF_FFFF);
    logic [31:0] rdata;
    read(addr, rdata);
    if ((rdata & mask) !== (exp_data & mask)) begin
      `uvm_error("APB_SEQ",
        $sformatf("READ_CHECK FAIL: addr=0x%08x exp=0x%08x got=0x%08x mask=0x%08x",
                  addr, exp_data, rdata, mask))
    end else begin
      `uvm_info("APB_SEQ",
        $sformatf("READ_CHECK PASS: addr=0x%08x data=0x%08x", addr, rdata), UVM_HIGH)
    end
  endtask

  virtual task body();
  endtask

endclass : apb_base_seq


// =============================================================================
// apb_slave_resp_seq - APB Slave 响应 Sequence（TLM FIFO 版本）
//
// 设计说明：
//   通过持有 apb_agent 句柄（p_agent）直接访问 agent 内部的 TLM FIFO：
//     req_fifo: 从 driver 获取观察到的总线请求
//     rsp_fifo: 向 driver 推送响应数据（rdata / wait_states / pslverr）
//
//   该方式绕过 uvm_sequencer 仲裁，避免原版 put/get 模式与
//   uvm_seq_item_pull_port 语义不符导致的挂起问题。
//
// 使用方法：
//   apb_slave_resp_seq slv_seq = apb_slave_resp_seq::type_id::create("slv_seq");
//   slv_seq.p_agent = apb_agt;           // 设置 agent 句柄
//   fork slv_seq.start(null); join_none  // 后台持续运行
//
// 可在运行时动态修改以下字段影响响应行为：
//   mem[addr]              : 预置或修改读数据
//   default_wait_states    : 全局等待状态数
//   default_pslverr        : 全局错误响应
//   pslverr_addrs[addr]=1  : 特定地址触发 PSLVERR
// =============================================================================
class apb_slave_resp_seq extends uvm_sequence_base;
  `uvm_object_utils(apb_slave_resp_seq)

  // apb_agent 句柄，由外部在 start() 前设置
  apb_agent p_agent;

  // 内置内存模型：写操作自动更新，读操作从此处返回数据
  logic [31:0] mem [logic [31:0]];

  // 全局默认响应配置（可在仿真运行中动态修改）
  int unsigned default_wait_states = 0;
  bit          default_pslverr     = 0;

  // 按地址注入 PSLVERR：pslverr_addrs[addr]=1 则该地址返回错误
  bit pslverr_addrs [logic [31:0]];

  function new(string name = "apb_slave_resp_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item req, rsp;

    if (p_agent == null)
      `uvm_fatal("APB_SLV_SEQ", "p_agent 未设置，请在 start() 前赋值")

    forever begin
      // 从 req_fifo 等待并获取 driver 观察到的总线请求
      p_agent.req_fifo.get(req);

      rsp = apb_seq_item::type_id::create("rsp");
      rsp.addr        = req.addr;
      rsp.rw          = req.rw;
      rsp.wdata       = req.wdata;
      rsp.wait_states = default_wait_states;
      rsp.pslverr     = pslverr_addrs.exists(req.addr) ? 1'b1 : default_pslverr;

      // 根据读写方向更新内存模型或填充读数据
      if (req.rw) begin
        // 写操作：更新内存（PSLVERR 时也更新，由测试自行决定是否验证）
        mem[req.addr] = req.wdata;
        `uvm_info("APB_SLV_SEQ",
          $sformatf("MEM WRITE: addr=0x%08x data=0x%08x ws=%0d pslverr=%0b",
                    req.addr, req.wdata, rsp.wait_states, rsp.pslverr), UVM_HIGH)
      end else begin
        // 读操作：从内存返回数据，未初始化地址返回特征值 0xDEAD_BEEF
        rsp.rdata = mem.exists(req.addr) ? mem[req.addr] : 32'hDEAD_BEEF;
        `uvm_info("APB_SLV_SEQ",
          $sformatf("MEM READ:  addr=0x%08x rdata=0x%08x ws=%0d pslverr=%0b",
                    req.addr, rsp.rdata, rsp.wait_states, rsp.pslverr), UVM_HIGH)
      end

      // 将响应推送给 rsp_fifo，driver 等待此数据后驱动总线
      p_agent.rsp_fifo.put(rsp);
    end
  endtask

endclass : apb_slave_resp_seq
