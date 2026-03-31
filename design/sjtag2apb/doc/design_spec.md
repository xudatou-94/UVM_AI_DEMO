# sjtag2apb 设计文档

## 功能概述

sjtag2apb 是一个协议转换桥，将 JTAG（IEEE 1149.1）串行接口转换为 APB 总线主端口，用于通过 JTAG 调试链访问片上 APB 外设寄存器。

---

## 模块结构

```
sjtag2apb_bridge（顶层）
├── sjtag_tap_ctrl    TAP 状态机（TCK 域）
├── IR 寄存器         指令寄存器（TCK 域）
├── DR 移位寄存器     APB_ACCESS / IDCODE / BYPASS（TCK 域）
├── TDO 驱动          下降沿输出（TCK 域）
├── CDC（TCK→PCLK）  Toggle 同步器，传递 APB 启动脉冲
├── APB 主状态机      IDLE/SETUP/ACCESS（PCLK 域）
└── CDC（PCLK→TCK）  读数据 2FF 同步回 TCK 域
```

---

## 时钟域设计

| 时钟域 | 包含逻辑 |
|---|---|
| `TCK` | TAP 状态机、IR 寄存器、DR 移位寄存器、TDO 输出 |
| `PCLK` | APB 主状态机、读数据寄存器 |

**跨时钟路径：**

- **TCK → PCLK**：`UPDATE_DR` 事件通过 Toggle 同步器传递。TCK 通常远低于 PCLK，Toggle 同步器（2FF）能保证控制信号可靠跨域。

- **PCLK → TCK**：APB 读数据通过 2FF 同步回 TCK 域。读数据在 `apb_done` 后保持准静态，TCK 域在下一次 `CAPTURE_DR`（通常在多个 PCLK 周期之后）才采样，数据充分稳定。

---

## 一、TAP 控制器

遵循 IEEE 1149.1 标准，共 **16 个状态**，TCK 上升沿采样 TMS 驱动状态转移，TRST_N 异步复位。

```
                         ┌─────────────────────────────┐
              TMS=1      │   TEST_LOGIC_RESET           │◄──── TRST_N
              ┌─────────►│   (复位状态，IR=BYPASS)      │
              │           └──────────┬──────────────────┘
              │              TMS=0   │
              │           ┌──────────▼──────────────────┐
              │           │   RUN_TEST_IDLE              │
              │           └──────────┬──────────────────┘
              │              TMS=1   │
              │           ┌──────────▼──────────────────┐
              │           │   SELECT_DR_SCAN             │
              │           └────┬─────────────────────────┘
              │         TMS=0  │  TMS=1
              │   DR 扫描路径  │        IR 扫描路径
              │  CAPTURE_DR    │      SELECT_IR→CAPTURE_IR
              │  SHIFT_DR      │      SHIFT_IR
              │  EXIT1_DR      │      EXIT1_IR
              │  PAUSE_DR      │      PAUSE_IR
              │  EXIT2_DR      │      EXIT2_IR
              │  UPDATE_DR─────┘      UPDATE_IR
              └──────────────────────────────────────────
```

**软复位**：TMS 连续 5 个 TCK 上升沿保持高电平，从任意状态回到 `TEST_LOGIC_RESET`，无需 TRST_N。

---

## 二、IR 指令集

IR 寄存器宽度为 **4 bit**，复位默认为 `BYPASS`（4'hF）。

| 指令 | 编码 | 功能 |
|---|---|---|
| `IDCODE`     | 4'h1 | 读取 32bit 设备 ID |
| `APB_ACCESS` | 4'h2 | 通过 JTAG 发起 APB 读/写事务 |
| `BYPASS`     | 4'hF | 旁路模式，DR 为 1bit，TDI 延迟一拍输出 |

**CAPTURE_IR** 时移位寄存器加载固定值 `4'b0001`（bit0=1，符合 IEEE 1149.1 规范，主机可检测 IR 长度）。

---

## 三、DR 寄存器

### APB_ACCESS DR（65 bit，LSB first）

```
bit[64]    : RW     写方向标志（1=写，0=读）
bit[63:32] : PADDR  APB 目标地址（32bit）
bit[31:0]  : DATA   写数据（写操作）/ 读数据（读操作回填）
```

移位方向：LSB first，TDI 移入最高位，最低位从 TDO 移出。

**写操作流程：**
```
1. SHIFT_IR  ──► 移入 4'h2（APB_ACCESS），LSB first
2. SHIFT_DR  ──► 移入 {1'b1, addr[31:0], wdata[31:0]}，共 65bit
3. UPDATE_DR ──► 桥锁存 DR，Toggle 同步器触发 PCLK 域 APB 写事务
```

**读操作流程：**
```
1. SHIFT_IR  ──► 移入 4'h2（APB_ACCESS）
2. SHIFT_DR  ──► 移入 {1'b0, addr[31:0], 32'h0}，共 65bit
3. UPDATE_DR ──► 桥发起 APB 读事务
4. （等待 APB 完成，读数据同步回 TCK 域）
5. CAPTURE_DR──► 读数据加载到 DR[31:0]
6. SHIFT_DR  ──► 从 TDO 移出 65bit，其中 bit[31:0] 为读数据
```

### IDCODE DR（32 bit）

固定值 `32'h5A7B_0001`（JEDEC 格式，bit0=1）。CAPTURE_DR 时重新加载，防止被篡改。

### BYPASS DR（1 bit）

CAPTURE_DR 加载 0，SHIFT_DR 时 TDI 直通，实现最短扫描路径。

---

## 四、APB 主状态机

工作在 PCLK 域，收到 `apb_start_pclk` 脉冲后启动标准 APB3 时序：

```
IDLE ──► SETUP（1 PCLK）──► ACCESS（等待 PREADY=1）──► IDLE
```

```
PCLK:    __|‾|__|‾|__|‾|__|‾|__|‾|__
PSEL:    ___________|‾‾‾‾‾‾‾‾‾‾‾‾|___
PENABLE: _______________|‾‾‾‾‾‾‾‾|___
PREADY:  _______________________|‾|___   ← slave 就绪（可含等待周期）
```

- **PSLVERR** 不影响状态机流转，错误信息由软件通过下一次 DR 读操作获知（通用设计）。
- ACCESS 阶段支持 **多周期等待**（PREADY=0 期间保持）。

---

## 五、CDC 设计

### TCK → PCLK（启动脉冲）

```
TCK 域：UPDATE_DR 发生时，apb_req_toggle 翻转
PCLK 域：2FF 同步后做边沿检测（XOR），产生单周期 apb_start_pclk 脉冲
```

Toggle 同步器保证每次 `UPDATE_DR` 只产生一次 APB 事务，不会丢失也不会重复。

### PCLK → TCK（读数据）

```
PCLK 域：APB 完成后 apb_rdata_q 保持稳定
TCK 域：2FF 同步 apb_rdata_q → apb_rdata_tck（准静态 CDC）
```

**数据有效性保证**：`UPDATE_DR` 触发 APB 事务，APB 完成需多个 PCLK 周期。软件必须在 APB 完成后（通常通过轮询或足够长的 RTI 延迟）再执行下一次 `CAPTURE_DR`，此时读数据已稳定至少 2 个 TCK 周期。

---

## 六、TDO 输出

TDO 在 **TCK 下降沿**更新，满足 JTAG 规范要求的输出建立时间（给主机在下一个 TCK 上升沿采样留出足够裕量）：

```
仅在 SHIFT_DR 或 SHIFT_IR 状态输出有效数据，其余状态输出高电平（idle 值）
```

数据来源 MUX：
- `APB_ACCESS` → `dr_apb_shift_q[0]`
- `IDCODE`     → `dr_idcode_shift_q[0]`
- `BYPASS`     → `dr_bypass_q`

---

## 七、顶层接口

### JTAG 端口

| 信号 | 方向 | 说明 |
|---|---|---|
| `tck`    | input  | JTAG 时钟 |
| `trst_n` | input  | 异步复位（低有效）|
| `tms`    | input  | 测试模式选择 |
| `tdi`    | input  | 串行数据输入 |
| `tdo`    | output | 串行数据输出（TCK 下降沿驱动）|

### APB 主端口

| 信号 | 方向 | 说明 |
|---|---|---|
| `pclk`    | input  | APB 时钟 |
| `presetn` | input  | APB 复位（低有效）|
| `psel`    | output | 从设备片选 |
| `penable` | output | 使能（ACCESS 阶段）|
| `pwrite`  | output | 写方向标志 |
| `paddr`   | output | 地址（32bit）|
| `pwdata`  | output | 写数据（32bit）|
| `prdata`  | input  | 读数据（32bit）|
| `pready`  | input  | 从设备就绪 |
| `pslverr` | input  | 从设备错误 |

---

## 八、参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `DEVICE_IDCODE` | 32'h5A7B_0001 | 设备 ID（JEDEC 格式，bit0=1）|
| `IR_LEN`        | 4  | IR 寄存器位宽（pkg 内定义）|
| `APB_ADDR_W`    | 32 | APB 地址位宽 |
| `APB_DATA_W`    | 32 | APB 数据位宽 |
| `DR_APB_LEN`    | 65 | APB_ACCESS DR 总位宽（1+32+32）|
