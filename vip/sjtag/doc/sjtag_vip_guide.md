# SJTAG VIP 使用手册

## 概述

SJTAG VIP 是一个 UVM Master-only VIP，用于模拟 JTAG 主机（调试器/控制器）向 DUT 发送 JTAG 序列。
支持 TAP 复位、IR/DR 移位操作，以及封装好的 APB 读写和 IDCODE 读取事务。

### 文件结构

```
vip/sjtag/
├── sjtag_if.sv          # JTAG 接口
├── sjtag_seq_item.sv    # 事务对象
├── sjtag_driver.sv      # Master Driver（含 TAP 状态机）
├── sjtag_monitor.sv     # 被动监听，重建 TAP 事务
├── sjtag_sequencer.sv   # UVM Sequencer
├── sjtag_agent_cfg.sv   # Agent 配置对象
├── sjtag_agent.sv       # Agent（active/passive）
├── sjtag_base_seq.sv    # 基础 Sequence（含原子操作任务）
├── sjtag_pkg.sv         # VIP 顶层 Package
├── sjtag.flist          # VCS 文件列表
└── doc/
    └── sjtag_vip_guide.md
```

---

## 快速上手

### 1. 在 dut.flist 中引入 VIP

```
-f ${REPO_ROOT}/vip/sjtag/sjtag.flist
```

### 2. 在 tb_top 中实例化接口并传递给 config_db

```systemverilog
module tb_top;
  import uvm_pkg::*;
  import sjtag_pkg::*;

  // 实例化接口
  sjtag_if sjtag_if_inst();

  // 连接 DUT
  sjtag2apb_top dut (
    .tck    (sjtag_if_inst.tck),
    .trst_n (sjtag_if_inst.trst_n),
    .tms    (sjtag_if_inst.tms),
    .tdi    (sjtag_if_inst.tdi),
    .tdo    (sjtag_if_inst.tdo),
    // ... 其他信号
  );

  initial begin
    uvm_config_db #(virtual sjtag_if)::set(null, "uvm_test_top.*", "vif", sjtag_if_inst);
    run_test();
  end
endmodule
```

### 3. 在 env 中创建 agent

```systemverilog
class my_env extends uvm_env;
  sjtag_agent sjtag_agt;

  function void build_phase(uvm_phase phase);
    sjtag_agent_cfg cfg;
    cfg = sjtag_agent_cfg::type_id::create("cfg");
    cfg.is_active          = UVM_ACTIVE;
    cfg.tck_half_period_ns = 50;  // 100ns TCK（10MHz）
    uvm_config_db #(sjtag_agent_cfg)::set(this, "sjtag_agt", "cfg", cfg);

    sjtag_agt = sjtag_agent::type_id::create("sjtag_agt", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // 连接 scoreboard 或 coverage collector
    // sjtag_agt.ap.connect(sb.sjtag_export);
  endfunction
endclass
```

### 4. 编写 Sequence 发送事务

```systemverilog
class my_sjtag_seq extends sjtag_base_seq;
  `uvm_object_utils(my_sjtag_seq)

  function new(string name = "my_sjtag_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] rdata;

    // TAP 复位
    do_reset();

    // APB 写操作
    apb_write(32'h0000_0000, 32'hDEAD_BEEF);

    // APB 读操作
    apb_read(32'h0000_0000, rdata);
    `uvm_info("MY_SEQ", $sformatf("读回数据: 0x%08x", rdata), UVM_MEDIUM)

    // 读取 IDCODE
    logic [31:0] idcode;
    read_idcode(idcode);
    `uvm_info("MY_SEQ", $sformatf("IDCODE: 0x%08x", idcode), UVM_MEDIUM)
  endtask
endclass
```

```systemverilog
class my_test extends uvm_test;
  task run_phase(uvm_phase phase);
    my_sjtag_seq seq;
    phase.raise_objection(this);
    seq = my_sjtag_seq::type_id::create("seq");
    seq.start(env.sjtag_agt.seqr);
    phase.drop_objection(this);
  endtask
endclass
```

---

## 配置参数说明

### sjtag_agent_cfg

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `is_active` | `uvm_active_passive_enum` | `UVM_ACTIVE` | ACTIVE：创建 driver+sequencer；PASSIVE：仅创建 monitor |
| `tck_half_period_ns` | `int unsigned` | `50` | TCK 半周期（ns），默认 100ns 周期（10MHz） |
| `has_monitor` | `bit` | `1` | 是否创建 monitor |

**修改 TCK 频率示例：**

```systemverilog
cfg.tck_half_period_ns = 25;  // 50ns 周期（20MHz）
cfg.tck_half_period_ns = 100; // 200ns 周期（5MHz）
```

---

## 事务类型（sjtag_seq_item）

| op 枚举值 | 说明 | 有效字段 |
|-----------|------|----------|
| `SJTAG_RESET` | TAP 软复位（5 个 TMS=1） | 无 |
| `SJTAG_APB_WRITE` | 通过 JTAG 向 APB 地址写数据 | `addr`、`wdata` |
| `SJTAG_APB_READ` | 通过 JTAG 从 APB 地址读数据 | `addr`；读回值填入 `rdata` |
| `SJTAG_IDCODE` | 读取设备 IDCODE | 读回值填入 `rdata` |

**约束：**
- `addr[1:0] == 2'b00`（4 字节对齐）

---

## Monitor 输出说明

Monitor 在以下时刻向 `ap`（`uvm_analysis_port`）广播事务：

- `UPDATE_DR` 时（DR 移位完成）：根据当前 IR 值解码并广播
  - IR=`4'h1`（IDCODE）：广播 `SJTAG_IDCODE` item，`rdata` 为移出的 32bit 值
  - IR=`4'h2`（APB_ACCESS）：广播 `SJTAG_APB_WRITE` 或 `SJTAG_APB_READ` item

Monitor 重建了完整的 TAP 状态机，可在 active 和 passive 两种模式下使用。

---

## TAP 协议说明

VIP 内部维护 TAP 状态机，遵循 IEEE 1149.1 标准：

```
                    TMS=1          TMS=1
RUN_TEST_IDLE ──────────→ SELECT_DR ──────→ SELECT_IR
      ↑               TMS=0 ↓          TMS=0 ↓
      │           CAPTURE_DR         CAPTURE_IR
      │           TMS=0 ↓            TMS=0 ↓
      │           SHIFT_DR           SHIFT_IR
      │    TMS=1 ↓                   TMS=1 ↓
      │    EXIT1_DR                  EXIT1_IR
      │    TMS=1 ↓                   TMS=1 ↓
      │    UPDATE_DR                 UPDATE_IR
      └──── TMS=0 ──────────────────── TMS=0
```

**移位规则：** LSB first（bit[0] 先移出/入）
**TDO 采样：** TCK 上升沿稳定后采样
**TMS/TDI 建立：** 在 TCK 上升沿前的半周期设置

---

## DR 格式（IR=APB_ACCESS，65bit）

```
bit[64]   : RW（1=写，0=读）
bit[63:32]: PADDR（APB 地址，32bit）
bit[31:0] : PWDATA（写数据）/ PRDATA（读数据，CAPTURE_DR 时由 DUT 载入）
```

**APB 读操作需要两次 DR 扫描：**
1. 第一次：发送读地址（RW=0），DUT 启动 APB 读事务
2. 等待若干 TCK（DUT 完成 APB 事务）
3. 第二次：CAPTURE_DR 时 DUT 将 PRDATA 载入 DR，移出读数据

---

## 被动监听模式（Passive）

仅需要监听总线时，将 agent 配置为 passive：

```systemverilog
cfg.is_active = UVM_PASSIVE;
// 无需连接 sequencer，直接连接 analysis_port
sjtag_agt.ap.connect(my_scoreboard.sjtag_export);
```

Passive 模式不创建 driver 和 sequencer，适合在 chip-level TB 中复用 VIP 进行协议检查。
