# APB VIP 使用手册

## 概述

APB VIP 是一个完整的 UVM APB 总线 VIP，同时支持 **Master** 和 **Slave** 两种角色，
遵循 AMBA APB3/APB4 规范，提供协议断言、等待状态配置、PSLVERR 响应等完整功能。

### 文件结构

```
vip/apb/
├── apb_if.sv              # APB 接口（含协议断言）
├── apb_seq_item.sv        # 事务对象
├── apb_agent_cfg.sv       # Agent 配置对象
├── apb_master_driver.sv   # Master Driver
├── apb_slave_driver.sv    # Slave Driver
├── apb_monitor.sv         # 被动监听
├── apb_sequencer.sv       # UVM Sequencer
├── apb_agent.sv           # Agent（master/slave/passive）
├── apb_base_seq.sv        # 基础 Sequence 及 Slave 响应基类
├── apb_pkg.sv             # VIP 顶层 Package
├── apb.flist              # VCS 文件列表
└── doc/
    └── apb_vip_guide.md
```

---

## 快速上手

### 1. 在 dut.flist 中引入 VIP

```
-f ${REPO_ROOT}/vip/apb/apb.flist
```

### 2. 在 tb_top 中实例化接口

`apb_if` 支持参数化地址/数据总线宽度，默认均为 32bit：

```systemverilog
module tb_top;
  import uvm_pkg::*;
  import apb_pkg::*;

  logic PCLK, PRESETn;

  // 实例化接口（默认 32bit 地址/数据）
  apb_if #(.ADDR_W(32), .DATA_W(32)) apb_if_inst(.PCLK(PCLK), .PRESETn(PRESETn));

  // 连接 DUT（Master 侧示例）
  my_dut dut (
    .PCLK    (PCLK),
    .PRESETn (PRESETn),
    .PADDR   (apb_if_inst.PADDR),
    .PSEL    (apb_if_inst.PSEL),
    .PENABLE (apb_if_inst.PENABLE),
    .PWRITE  (apb_if_inst.PWRITE),
    .PWDATA  (apb_if_inst.PWDATA),
    .PRDATA  (apb_if_inst.PRDATA),
    .PREADY  (apb_if_inst.PREADY),
    .PSLVERR (apb_if_inst.PSLVERR)
  );

  initial begin
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.*", "vif", apb_if_inst);
    run_test();
  end
endmodule
```

---

## Master 模式

### 配置 Agent 为 Master

```systemverilog
class my_env extends uvm_env;
  apb_agent apb_agt;

  function void build_phase(uvm_phase phase);
    apb_agent_cfg cfg;
    cfg        = apb_agent_cfg::type_id::create("cfg");
    cfg.role      = apb_agent_cfg::APB_MASTER;
    cfg.is_active = UVM_ACTIVE;
    uvm_config_db #(apb_agent_cfg)::set(this, "apb_agt", "cfg", cfg);

    apb_agt = apb_agent::type_id::create("apb_agt", this);
  endfunction
endclass
```

### Master Sequence 示例

继承 `apb_base_seq`，使用内置的 `write` / `read` / `read_check` 任务：

```systemverilog
class reg_config_seq extends apb_base_seq;
  `uvm_object_utils(reg_config_seq)

  function new(string name = "reg_config_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] rdata;

    // 写寄存器
    write(32'h0000_0000, 32'hA5A5_0001);
    write(32'h0000_0004, 32'h0000_0010);

    // 读寄存器
    read(32'h0000_0000, rdata);
    `uvm_info("SEQ", $sformatf("读回: 0x%08x", rdata), UVM_MEDIUM)

    // 读并核验（带 mask）
    read_check(32'h0000_0004, 32'h0000_0010, 32'hFFFF_FFFF);
  endtask
endclass
```

启动 sequence：

```systemverilog
class my_test extends uvm_test;
  task run_phase(uvm_phase phase);
    reg_config_seq seq;
    phase.raise_objection(this);
    seq = reg_config_seq::type_id::create("seq");
    seq.start(env.apb_agt.seqr);
    phase.drop_objection(this);
  endtask
endclass
```

---

## Slave 模式

### 配置 Agent 为 Slave

```systemverilog
apb_agent_cfg cfg;
cfg = apb_agent_cfg::type_id::create("cfg");
cfg.role                 = apb_agent_cfg::APB_SLAVE;
cfg.is_active            = UVM_ACTIVE;
cfg.default_wait_states  = 0;   // 默认无等待
cfg.default_pslverr      = 0;   // 默认无错误
uvm_config_db #(apb_agent_cfg)::set(this, "apb_slv_agt", "cfg", cfg);
```

### Slave Sequence 示例

#### 方式一：使用内置内存模型（apb_slave_resp_seq）

`apb_slave_resp_seq` 内置了一个关联数组内存模型，并通过 TLM FIFO 与 slave driver 通信。
使用前需设置 `p_agent` 句柄，然后在后台 fork 启动：

```systemverilog
class my_env extends uvm_env;
  apb_agent            apb_slv_agt;
  apb_slave_resp_seq   apb_slv_seq;

  function void build_phase(uvm_phase phase);
    apb_agent_cfg cfg = apb_agent_cfg::type_id::create("cfg");
    cfg.role      = apb_agent_cfg::APB_SLAVE;
    cfg.is_active = UVM_ACTIVE;
    uvm_config_db #(apb_agent_cfg)::set(this, "apb_slv_agt", "cfg", cfg);
    apb_slv_agt = apb_agent::type_id::create("apb_slv_agt", this);
    apb_slv_seq = apb_slave_resp_seq::type_id::create("apb_slv_seq");
  endfunction

  task run_phase(uvm_phase phase);
    // 预置内存值（可在 run_phase 启动前配置）
    apb_slv_seq.mem[32'h0000_0000] = 32'h1234_5678;
    // 设置 agent 句柄并后台运行
    apb_slv_seq.p_agent = apb_slv_agt;
    fork apb_slv_seq.start(null); join_none
  endtask
endclass
```

#### 方式二：运行时动态配置响应行为

`apb_slave_resp_seq` 暴露以下字段，可在仿真运行中随时修改：

```systemverilog
// 修改全局等待状态数
env.apb_slv_seq.default_wait_states = 3;

// 预置或修改某地址的读数据
env.apb_slv_seq.mem[32'h0000_0010] = 32'hDEAD_CAFE;

// 对特定地址注入 PSLVERR
env.apb_slv_seq.pslverr_addrs[32'hBAD_ADDR] = 1;

// 清除 PSLVERR 注入
env.apb_slv_seq.pslverr_addrs.delete(32'hBAD_ADDR);
```

#### 方式三：自定义响应逻辑

继承 `apb_slave_resp_seq` 并重写 `body`，通过相同的 TLM FIFO 接口实现复杂响应：

```systemverilog
class err_inject_slave_seq extends apb_slave_resp_seq;
  `uvm_object_utils(err_inject_slave_seq)

  logic [31:0] err_addr = 32'h0000_00FF;

  task body();
    apb_seq_item req, rsp;
    forever begin
      // 从 req_fifo 获取 driver 观察到的总线请求
      p_agent.req_fifo.get(req);

      rsp = apb_seq_item::type_id::create("rsp");
      rsp.addr = req.addr;
      rsp.rw   = req.rw;

      if (req.addr == err_addr) begin
        rsp.pslverr     = 1;
        rsp.wait_states = 2;
      end else begin
        rsp.pslverr     = 0;
        rsp.wait_states = $urandom_range(0, 3);
        if (!req.rw)
          rsp.rdata = mem.exists(req.addr) ? mem[req.addr] : 32'hDEAD_BEEF;
        else
          mem[req.addr] = req.wdata;
      end

      // 向 rsp_fifo 推送响应，driver 收到后驱动总线
      p_agent.rsp_fifo.put(rsp);
    end
  endtask
endclass
```

---

## 配置参数说明

### apb_agent_cfg

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `is_active` | `uvm_active_passive_enum` | `UVM_ACTIVE` | ACTIVE：创建 driver+sequencer；PASSIVE：仅创建 monitor |
| `role` | `apb_role_e` | `APB_MASTER` | 角色：`APB_MASTER` 或 `APB_SLAVE` |
| `default_wait_states` | `int unsigned` | `0` | Slave 模式默认等待状态数 |
| `default_pslverr` | `bit` | `0` | Slave 模式默认错误响应 |
| `has_monitor` | `bit` | `1` | 是否创建 monitor |
| `addr_width` | `int unsigned` | `32` | 地址总线宽度（须与 apb_if 参数一致） |
| `data_width` | `int unsigned` | `32` | 数据总线宽度（须与 apb_if 参数一致） |

---

## 事务字段说明（apb_seq_item）

| 字段 | 方向 | 说明 |
|------|------|------|
| `addr[31:0]` | rand | APB 地址（PADDR），4 字节对齐约束 |
| `rw` | rand | 1=写（PWRITE=1），0=读（PWRITE=0） |
| `wdata[31:0]` | rand | 写数据（PWDATA），写操作时有效 |
| `rdata[31:0]` | 输出 | 读数据（PRDATA），由 driver/monitor 填入 |
| `pslverr` | 输出 | 从设备错误标志，由 slave driver/monitor 填入 |
| `pprot[2:0]` | rand | APB4 保护属性（默认 3'b000） |
| `pstrb[3:0]` | rand | APB4 写字节使能（写时默认 4'hF） |
| `wait_states` | rand | Slave 插入的等待周期数（0~7，可自定义约束） |

---

## Monitor 说明

Monitor 在 `PSEL & PENABLE & PREADY` 同时为高的时钟上升沿采样事务，
通过 `ap`（`uvm_analysis_port`）广播 `apb_seq_item`。

连接示例：

```systemverilog
// 连接到 scoreboard
apb_agt.ap.connect(scoreboard.apb_export);

// 同时连接多个订阅者（使用 uvm_analysis_port 广播）
apb_agt.ap.connect(scoreboard.apb_export);
apb_agt.ap.connect(coverage_collector.apb_export);
```

---

## 协议断言

`apb_if` 内置以下 SVA 断言，仿真期间自动激活（`ifndef SYNTHESIS` 保护）：

| 断言名 | 检查内容 |
|--------|---------|
| `p_setup_penable` | SETUP 阶段（PSEL 上升沿）PENABLE 必须为 0 |
| `p_access_penable` | PSEL 有效后下一拍 PENABLE 必须拉高 |
| `p_addr_stable` | 等待期间（PREADY=0）PADDR 不能变化 |

违例时输出 `UVM_ERROR` 级别报错，便于发现总线时序问题。

---

## 被动监听模式（Passive）

在 chip-level 或 subsystem-level 仅需监听 APB 总线时：

```systemverilog
apb_agent_cfg cfg;
cfg = apb_agent_cfg::type_id::create("cfg");
cfg.is_active = UVM_PASSIVE;  // 不创建 driver/sequencer
cfg.has_monitor = 1;
uvm_config_db #(apb_agent_cfg)::set(this, "apb_mon_agt", "cfg", cfg);

// 连接分析端口
apb_mon_agt.ap.connect(scoreboard.apb_export);
```

---

## Master + Slave 联合使用示例

在同一 TB 中同时使用 master 和 slave（例如验证总线仲裁或 bridge 模块）：

```systemverilog
class bridge_env extends uvm_env;
  apb_agent apb_master_agt;  // master：驱动上游请求
  apb_agent apb_slave_agt;   // slave：模拟下游从设备

  function void build_phase(uvm_phase phase);
    apb_agent_cfg mst_cfg, slv_cfg;

    mst_cfg       = apb_agent_cfg::type_id::create("mst_cfg");
    mst_cfg.role  = apb_agent_cfg::APB_MASTER;
    uvm_config_db #(apb_agent_cfg)::set(this, "apb_master_agt", "cfg", mst_cfg);

    slv_cfg       = apb_agent_cfg::type_id::create("slv_cfg");
    slv_cfg.role  = apb_agent_cfg::APB_SLAVE;
    slv_cfg.default_wait_states = 1;
    uvm_config_db #(apb_agent_cfg)::set(this, "apb_slave_agt", "cfg", slv_cfg);

    apb_master_agt = apb_agent::type_id::create("apb_master_agt", this);
    apb_slave_agt  = apb_agent::type_id::create("apb_slave_agt",  this);
  endfunction
endclass
```

---

## Slave Driver 设计说明（TLM FIFO 方案）

### 原版本问题

初始版本的 `apb_slave_driver` 继承自 `uvm_driver #(apb_seq_item)`，
在 `respond_to_transfer()` 中通过以下方式与 sequencer 通信：

```systemverilog
seq_item_port.put(req);   // 尝试将请求推送给 sequencer
seq_item_port.get(rsp);   // 尝试从 sequencer 获取响应
```

**根本问题**：`seq_item_port` 的类型是 `uvm_seq_item_pull_port`，其设计语义是
**"sequencer 产生激励 → driver 拉取"**。而 APB slave 的场景恰恰相反——激励来自总线
（DUT 是 APB master），driver 需要被动响应。对 `uvm_seq_item_pull_port` 调用 `put()`
在标准 `uvm_sequencer` 上没有对应的接收端，会导致调用永久阻塞。

### 修正方案（TLM FIFO 双向通信）

```
                 req_fifo（深度=1）
slave_drv ──put(observed_req)──> ──get──> apb_slave_resp_seq
          <──get(response)────── <──put── apb_slave_resp_seq
                 rsp_fifo（深度=1）
```

| 组件 | 变化 |
|------|------|
| `apb_slave_driver` | 改继承 `uvm_component`，去掉 `seq_item_port`；新增 `req_port`（put）和 `rsp_port`（get）|
| `apb_agent` | slave 模式下额外创建 `req_fifo` / `rsp_fifo`；connect_phase 连接 driver 端口到 FIFO |
| `apb_slave_resp_seq` | 改继承 `uvm_sequence_base`；通过 `p_agent.req_fifo.get()` / `p_agent.rsp_fifo.put()` 收发数据 |

**FIFO 深度为 1** 的原因：APB 总线是单请求单响应协议，不允许请求积压；深度 1 确保
driver 和 sequence 严格按照"一请求一响应"配对，避免响应错位。
