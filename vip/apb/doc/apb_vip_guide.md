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

`apb_slave_resp_seq` 内置了一个简单的关联数组内存，写操作存储数据，读操作返回存储值：

```systemverilog
class mem_slave_test extends uvm_test;
  task run_phase(uvm_phase phase);
    apb_slave_resp_seq slv_seq;
    phase.raise_objection(this);
    slv_seq = apb_slave_resp_seq::type_id::create("slv_seq");
    // 预置初始内存值
    slv_seq.mem[32'h0000_0000] = 32'h1234_5678;
    slv_seq.start(env.apb_slv_agt.seqr);
    phase.drop_objection(this);
  endtask
endclass
```

#### 方式二：自定义响应逻辑

继承 `apb_slave_resp_seq` 并重写 `body`，实现更复杂的响应行为（如错误注入、延迟变化）：

```systemverilog
class err_inject_slave_seq extends apb_slave_resp_seq;
  `uvm_object_utils(err_inject_slave_seq)

  logic [31:0] err_addr = 32'h0000_00FF;  // 此地址触发 PSLVERR

  task body();
    apb_seq_item req, rsp;
    forever begin
      p_sequencer.wait_for_sequences();
      if (p_sequencer.has_do_available()) begin
        `uvm_create(req)
        `uvm_rand_send(req)

        rsp = apb_seq_item::type_id::create("rsp");
        rsp.copy(req);

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
      end
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
