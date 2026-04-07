# AXI4 VIP 使用指南

## 1. 文件结构

```
vip/axi/
├── axi_pkg.sv           基础类型定义（枚举、参数）
├── axi_if.sv            AXI4 SystemVerilog Interface（含 SVA）
├── axi_seq_item.sv      事务对象（写/读 + 反压配置）
├── axi_agent_cfg.sv     Agent 配置对象
├── axi_sequencer.sv     Sequencer（typedef）
├── axi_master_driver.sv Master Driver（6进程 outstanding）
├── axi_slave_driver.sv  Slave Driver（响应式，TLM FIFO）
├── axi_monitor.sv       被动监控器（重建完整事务）
├── axi_agent.sv         Agent（master/slave/passive 三模式）
├── axi_base_seq.sv      基础 Sequence 集合
├── axi_vip_pkg.sv       顶层 Package
├── axi.flist            VCS 编译文件列表
└── doc/
    └── axi_vip_guide.md 本文档
```

---

## 2. 快速开始

### 2.1 TB 顶层连接

```systemverilog
// tb_top.sv
`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_pkg::*;
import axi_vip_pkg::*;

module tb_top;
  logic aclk, aresetn;

  // 时钟复位生成
  initial aclk = 0;
  always #5 aclk = ~aclk;
  initial begin
    aresetn = 0;
    repeat(10) @(posedge aclk);
    aresetn = 1;
  end

  // AXI 接口实例
  axi_if axi_bus(.aclk(aclk), .aresetn(aresetn));

  // DUT 连接
  dut u_dut(
    .aclk     (axi_bus.aclk),
    .aresetn  (axi_bus.aresetn),
    .awvalid  (axi_bus.awvalid), ...
  );

  // 将接口注册到 config_db
  initial begin
    uvm_config_db #(virtual axi_if.master_mp)::set(null,
      "uvm_test_top.env.master_agent.*", "vif", axi_bus.master_mp);
    uvm_config_db #(virtual axi_if.slave_mp)::set(null,
      "uvm_test_top.env.slave_agent.*",  "vif", axi_bus.slave_mp);
    uvm_config_db #(virtual axi_if.monitor_mp)::set(null,
      "uvm_test_top.env.monitor.*",      "vif", axi_bus.monitor_mp);
    run_test();
  end
endmodule
```

### 2.2 Env 搭建

```systemverilog
class axi_env extends uvm_env;
  axi_agent  master_agent;
  axi_agent  slave_agent;

  function void build_phase(uvm_phase phase);
    // Master 配置：最大 outstanding=4
    axi_agent_cfg m_cfg = axi_agent_cfg::create_master_cfg("m_cfg", 4);
    uvm_config_db #(axi_agent_cfg)::set(this, "master_agent", "cfg", m_cfg);

    // Slave 配置：ARREADY 最多延迟 2 拍
    axi_agent_cfg s_cfg = axi_agent_cfg::create_slave_cfg("s_cfg");
    s_cfg.arready_bp_mode = AXI_BP_RANDOM;
    s_cfg.arready_bp_min  = 0;
    s_cfg.arready_bp_max  = 2;
    uvm_config_db #(axi_agent_cfg)::set(this, "slave_agent", "cfg", s_cfg);

    master_agent = axi_agent::type_id::create("master_agent", this);
    slave_agent  = axi_agent::type_id::create("slave_agent",  this);
  endfunction
endclass
```

---

## 3. 发送事务

### 3.1 单次写

```systemverilog
// 方式 A：使用辅助任务（推荐）
class my_write_test extends uvm_test;
  task run_phase(uvm_phase phase);
    axi_write_seq seq;
    phase.raise_objection(this);
    seq = axi_write_seq::type_id::create("seq");
    seq.addr = 32'h1000;
    seq.data = 32'hDEAD_BEEF;
    seq.start(env.master_agent.sequencer);
    `uvm_info("TEST", $sformatf("resp=%s", seq.resp.name()), UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
```

### 3.2 Burst 写

```systemverilog
axi_seq_item item;
`uvm_do_with(item, {
  txn_type == AXI_WRITE;
  awaddr   == 32'h2000;
  awlen    == 8'h3;          // 4 beats
  awburst  == AXI_BURST_INCR;
  wdata.size() == 4;
})
```

### 3.3 带反压的读

```systemverilog
axi_read_seq seq = axi_read_seq::type_id::create("seq");
seq.addr             = 32'h3000;
seq.rready_bp_mode   = AXI_BP_RANDOM;
seq.rready_bp_min    = 1;
seq.rready_bp_max    = 5;   // RREADY 每拍随机延迟 1-5 周期
seq.start(env.master_agent.sequencer);
```

### 3.4 先写后读（自动比较）

```systemverilog
axi_rw_seq seq = axi_rw_seq::type_id::create("seq");
seq.addr = 32'h4000;
seq.data = 32'hCAFE_BABE;
seq.start(env.master_agent.sequencer);
// 写入数据 != 读回数据时自动打印 UVM_ERROR
```

---

## 4. Outstanding 实现原理

### 4.1 设计目标

AXI4 允许 master 在未收到响应前继续发出新事务（**流水线**），即同时存在多笔 in-flight 事务。VIP 通过以下机制支持该特性：

### 4.2 核心结构

| 结构 | 作用 |
|------|------|
| `sem_wr (semaphore)` | 写方向 outstanding 槽位计数，初始值 = `cfg.max_outstanding` |
| `sem_rd (semaphore)` | 读方向 outstanding 槽位计数 |
| `wr_inflight[awid]` | 关联数组，key=awid，value=飞行中的写事务 |
| `rd_inflight[arid]` | 关联数组，key=arid，value=飞行中的读事务 |

### 4.3 流程图

```
feed_transactions
   │  get_next_item(item)
   │  push item to wr_item_q / rd_item_q
   │  wait done_event[id]
   │  item_done()
   │
   ├─ drive_aw_channel
   │    sem_wr.get(1)          ← 申请槽位（满时阻塞）
   │    wr_inflight[id] = item
   │    drive AW handshake
   │    w_gate.put(1)          → 通知 W 通道
   │
   ├─ drive_w_channel
   │    w_gate.get(1)          ← 等待 AW 完成
   │    drive W beats (with WREADY backpressure)
   │
   └─ handle_b_channel
        wait BVALID
        apply BREADY backpressure
        item.bresp = vif.bresp
        wr_inflight.delete(id)
        ->wr_done_ev[id]       → 通知 feed 事务完成
        sem_wr.put(1)          → 归还槽位
```

### 4.4 关键特性

- **多事务并行**：`sem_wr` 允许最多 `max_outstanding` 笔写同时飞行，AW/W 通道持续推进而无需等待 B 响应
- **ID 匹配**：B/R 通道以 `bid`/`rid` 为 key 查找 `wr_inflight`/`rd_inflight`，正确匹配乱序响应
- **W 通道保序**：AXI4 规范要求 W 数据与地址通道保序，`awid_sent_q` + `w_gate` 确保顺序发送
- **反压独立**：BREADY 反压在已知 `bid` 后才应用（per-transaction），WREADY 反压在 W beat 发送前应用

---

## 5. 反压配置

### 5.1 反压信号覆盖范围

| 信号 | 配置位置 | 粒度 |
|------|----------|------|
| `BREADY` | `seq_item.bready_bp_*` | per-transaction（master 侧） |
| `RREADY` | `seq_item.rready_bp_*` | per-transaction（master 侧） |
| `WREADY` | `seq_item.wready_bp_*` | per-transaction（slave 侧） |
| `AWREADY` | `agent_cfg.awready_bp_*` | 全局（V1 限制）|
| `ARREADY` | `agent_cfg.arready_bp_*` | 全局（V1 限制）|

> **V1 限制说明**：AWREADY/ARREADY 为全局配置，原因是 slave 在 VALID 到来前无法预知是哪笔事务，无法按事务差异化控制。V2 可通过 callback 机制在 VALID 采样后动态调整。

### 5.2 反压模式

| 模式 | 说明 |
|------|------|
| `AXI_BP_NONE` | 无延迟（默认）|
| `AXI_BP_FIXED` | 固定 N 拍延迟，由 `*_bp_fixed` 指定 |
| `AXI_BP_RANDOM` | 随机延迟，范围 `[*_bp_min, *_bp_max]` |

---

## 6. Monitor 使用

Monitor 重建完整事务并通过两个 analysis port 广播：

```systemverilog
// 在 scoreboard / coverage collector 中连接
master_agent.ap_write.connect(scoreboard.wr_export);
master_agent.ap_read.connect(scoreboard.rd_export);
```

监控到的 `axi_seq_item` 包含完整的地址、数据、响应信息，适合用于：
- 功能覆盖率收集
- 参考模型比对（scoreboard）
- 总线活动日志

---

## 7. 编译命令

```makefile
# 在 verif/<proj>/Makefile 中引用 VIP
VIP_FLIST = $(REPO_ROOT)/vip/axi/axi.flist

compile:
    vcs -sverilog -f $(VIP_FLIST) -f tb.flist ...
```

或通过工程 make 框架：

```bash
cd verif/<proj>
make compile
make run TC=axi_write_test
```
