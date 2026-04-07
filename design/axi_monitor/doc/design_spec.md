# axi_monitor 设计文档

## 功能概述

axi_monitor 是一个被动监控组件，挂接在 AXI 总线旁路，不干预总线传输。通过 APB 接口进行配置和结果读取。包含两个功能模块：**PMU**（性能监控）和 **Trace**（事务追踪）。

---

## 模块结构

```
axi_monitor_top
├── axi_monitor_regfile   APB 寄存器文件（clk 域）
├── axi_monitor_pmu       性能计数器（clk 域，监控 ch0）
├── axi_ch_cdc [N_CH]     每通道 AXI 事件跨时钟同步（axi_clk → trace_clk）
└── axi_monitor_trace     事务追踪与 SRAM 记录（trace_clk 域）
```

---

## 时钟域设计

| 时钟 | 说明 |
|---|---|
| `clk` | APB 时钟，也是 PMU 工作时钟，监控 ch0 |
| `axi_clk[N_CH-1:0]` | 每个 AXI 通道独立时钟，可各不相同 |
| `trace_clk` | Trace 模块工作时钟，**必须是所有 axi_clk 中频率最高者** |

跨时钟路径：`axi_clk[i] → trace_clk`，由 `axi_ch_cdc` 处理。

---

## 一、PMU 模块

### 功能

以可配置的周期（`PMU_PERIOD` 个 `clk` 周期）为统计窗口，在每个窗口结束时将本窗口内的握手计数**快照**到寄存器，供软件读取，同时计数器归零开始下一个窗口。

### 统计项

| 统计项 | 条件 |
|---|---|
| AW 通道请求数 | `AWVALID & AWREADY` |
| W 通道请求数 | `WVALID & WREADY` |
| B 通道响应数 | `BVALID & BREADY` |
| AR 通道请求数 | `ARVALID & ARREADY` |
| R 通道响应数 | `RVALID & RREADY` |
| B 响应错误数 | `BVALID & BREADY & BRESP[1]`（SLVERR / DECERR）|
| R 响应错误数 | `RVALID & RREADY & RRESP[1]`（SLVERR / DECERR）|

`RESP[1]=1` 表示错误响应（`2'b10`=SLVERR，`2'b11`=DECERR）。

### 快照时序

```
周期 N 结束（period_done）时：
  snap_* ← cnt_* + 当拍握手数   // 含 period_done 同拍发生的握手
  cnt_*  ← 0                    // 下一周期重新计数
```

---

## 二、Trace 模块

### 功能

对 AXI 总线事务按条件进行过滤，命中时将事务信息写入片上 SRAM，软件通过寄存器命令读出。

### 工作时钟

Trace 模块工作在 `trace_clk` 域。所有输入事件均来自 `axi_ch_cdc` 的同步输出，内部无跨时钟路径。

### 通道选择

通过 `TRACE_CH_SEL` 寄存器选择监控哪一路 AXI 总线（0 ~ N_CH-1）。切换通道立即生效（组合逻辑 MUX）。

### 条件配置

每次只支持一个条件（字段 + 运算符 + 基准值）：

**条件字段（TRACE_COND_FIELD）**

| 编码 | 字段 | 触发时机 |
|---|---|---|
| 0 | AW_ADDR | AW 握手 |
| 1 | AR_ADDR | AR 握手 |
| 2 | W_DATA  | W 握手 |
| 3 | R_DATA  | R 握手 |
| 4 | AW_ID   | AW 握手 |
| 5 | AR_ID   | AR 握手 |
| 6 | BURST   | AW 或 AR 握手（同时发生优先记录写通道）|

**比较运算符（TRACE_COND_OP）**

| 编码 | 运算符 |
|---|---|
| 0 | == |
| 1 | != |
| 2 | >  |
| 3 | <  |
| 4 | >= |
| 5 | <= |

### SRAM 记录格式

每条记录 82 bit：

| 字段 | 位宽 | 说明 |
|---|---|---|
| addr | 32 | 事务地址（W/R 触发时为 0）|
| data | 32 | 数据（AW/AR 触发时为 0）|
| id   | 8  | 事务 ID（W 触发时为 0）|
| burst| 2  | Burst 类型（W/R 触发时为 0）|
| outstanding | 8 | 触发时的 outstanding 数量 |

outstanding 由 `trace_clk` 域内从同步事件重新推导：
- 写 outstanding：AW 事件 +1，B 事件 -1
- 读 outstanding：AR 事件 +1，R 事件 -1

### SRAM 管理

- 深度：32 条（`TRACE_DEPTH`，可通过参数调整）
- 写满后停止写入（新事件丢弃），`sram_full` 置位
- `trace_clr`（写 TRACE_CTRL[1]=1）清空 SRAM，复位读写指针和计数

### 软件读出流程

```
1. 读 TRACE_STATUS，确认 empty=0
2. 写 TRACE_RD_CMD[0]=1（单次脉冲）
3. 硬件将当前头部条目锁存到读出寄存器，读指针后移，count-1
4. 读取 TRACE_RD_ADDR / TRACE_RD_DATA / TRACE_RD_ID /
        TRACE_RD_BURST / TRACE_RD_OSD
```

---

## 三、CDC 模块（axi_ch_cdc）

### 设计方案

每个 AXI 通道（共 N_CH 路）各例化一个 `axi_ch_cdc`，将 5 类握手事件从 `axi_clk[i]` 同步到 `trace_clk`。

针对每类握手（AW / W / B / AR / R）独立使用 **Toggle 同步器**：

```
src_clk 域：
  握手发生 → 捕获数据到 cap_* 寄存器 → 翻转 req_toggle

dst_clk 域（trace_clk）：
  3FF 同步 req_toggle → 边沿检测 → 输出 *_event 脉冲
  同拍将 cap_* 锁存到输出寄存器
```

使用 3FF（而非标准 2FF）以在高频 `trace_clk` 下提供更充裕的建立时间裕量。

### 输出时序

```
trace_clk:  __|‾|__|‾|__|‾|__|‾|__
aw_event:   _____|‾|_____________    ← 单周期脉冲
aw_addr:    -----[稳定有效]------    ← 与 aw_event 同拍更新，之后保持
```

### 已知限制

若 `axi_clk[i]` 连续两拍发生同类握手（back-to-back），第二拍数据会覆盖捕获寄存器，`trace_clk` 侧可能读到第二笔数据，第一笔丢失。对于调试/监控用途此行为可接受；如需无损捕获，应将 `axi_ch_cdc` 替换为异步 FIFO 方案。

---

## 四、寄存器映射

### PMU 区域（base + 0x000）

| 地址   | 名称            | 属性 | 说明 |
|--------|-----------------|------|------|
| 0x000  | PMU_CTRL        | RW   | [0]=pmu_en |
| 0x004  | PMU_PERIOD      | RW   | 统计周期（clk 数，默认 1000）|
| 0x008  | PMU_AW_CNT      | RO   | AW 握手快照 |
| 0x00C  | PMU_W_CNT       | RO   | W 握手快照 |
| 0x010  | PMU_B_CNT       | RO   | B 握手快照 |
| 0x014  | PMU_AR_CNT      | RO   | AR 握手快照 |
| 0x018  | PMU_R_CNT       | RO   | R 握手快照 |
| 0x01C  | PMU_B_ERR_CNT   | RO   | BRESP 错误快照 |
| 0x020  | PMU_R_ERR_CNT   | RO   | RRESP 错误快照 |

### Trace 区域（base + 0x100）

| 地址   | 名称              | 属性 | 说明 |
|--------|-------------------|------|------|
| 0x100  | TRACE_CTRL        | RW   | [0]=trace_en，[1]=trace_clr（W1P）|
| 0x104  | TRACE_COND_FIELD  | RW   | 条件字段选择 [2:0] |
| 0x108  | TRACE_COND_OP     | RW   | 比较运算符 [2:0] |
| 0x10C  | TRACE_COND_VAL    | RW   | 比较基准值 [31:0] |
| 0x110  | TRACE_STATUS      | RO   | [0]=empty，[6:1]=count，[7]=full |
| 0x114  | TRACE_RD_CMD      | RW   | [0]=rd_req（W1P）|
| 0x118  | TRACE_RD_ADDR     | RO   | 读出条目：地址 |
| 0x11C  | TRACE_RD_DATA     | RO   | 读出条目：数据 |
| 0x120  | TRACE_RD_ID       | RO   | 读出条目：ID [7:0] |
| 0x124  | TRACE_RD_BURST    | RO   | 读出条目：Burst [1:0] |
| 0x128  | TRACE_RD_OSD      | RO   | 读出条目：outstanding [7:0] |
| 0x12C  | TRACE_CH_SEL      | RW   | 监控通道选择 [N_CH_W-1:0] |

---

## 五、顶层参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `AXI_ADDR_W` | 32 | AXI 地址位宽 |
| `AXI_DATA_W` | 32 | AXI 数据位宽 |
| `AXI_ID_W`   | 8  | AXI ID 位宽 |
| `N_CH`       | 4  | 监控通道数 |
| `TRACE_DEPTH`| 32 | SRAM 深度（条目数）|
| `OUTSTANDING_W` | 8 | outstanding 计数器位宽 |
| `PMU_CNT_W`  | 32 | PMU 计数器位宽 |
