# OTBN 验证环境运行指南

OpenTitan Big Number Accelerator (OTBN) UVM 验证环境，基于从 OpenTitan 抽取的 RTL 和自研 TL-UL Agent 搭建。

支持两种工作目录：

- **模块目录**（推荐单模块开发调试）：在 `verif/otbn/` 下直接执行，`PROJ` 自动推导
- **scripts 目录**（多模块统一管理）：在 `scripts/` 下执行，需显式传入 `PROJ=otbn`

以下示例均以**模块目录**为工作目录：

```bash
cd verif/otbn/
```

---

## 环境初始化

```bash
source ../../scripts/setup.sh
```

---

## 编译

```bash
make compile
```

等价于（在 scripts 目录）：

```bash
make compile PROJ=otbn
```

---

## 单条激励运行

```bash
# 仅运行（需已编译）
make run TC=<test_class>

# 编译 + 运行一步完成
make all TC=<test_class>
```

### 测试用例列表

| case_id    | case_name    | TC（测试类名）      | 说明                                  |
|------------|--------------|---------------------|---------------------------------------|
| otbn_0001  | otbn_smoke   | `otbn_smoke_test`   | 加载单条 ECALL，运行，验证 IDLE+无错误 |
| otbn_0002  | otbn_dmem_rw | `otbn_dmem_rw_test` | 写 DMEM pattern，执行，读回比对        |

### 运行示例

```bash
# 编译 + 运行 smoke 测试
make all TC=otbn_smoke_test

# 指定随机种子
make all TC=otbn_smoke_test SEED=12345

# 提高 UVM 打印级别
make all TC=otbn_smoke_test VERBOSITY=UVM_HIGH

# 关闭波形（加速仿真）
make all TC=otbn_dmem_rw_test WAVE=0

# 运行 DMEM 读写测试
make all TC=otbn_dmem_rw_test SEED=42
```

---

## 批量回归

运行全部用例：

```bash
make regress
```

按标签过滤：

```bash
# 只运行 smoke 标签（otbn_0001 + otbn_0002）
make regress TAG=smoke

# 只运行 dmem 相关
make regress TAG=dmem
```

并行运行：

```bash
make regress JOBS=4
```

开启覆盖率：

```bash
# 代码覆盖率
make regress CODE_COV=1

# 功能覆盖率
make regress FUNC_COV=1

# 同时开启
make regress CODE_COV=1 FUNC_COV=1 JOBS=4
```

---

## 重跑失败用例

```bash
make rerun
```

---

## 合并覆盖率

```bash
make merge_cov
```

---

## 波形调试

```bash
# 打开最新仿真波形
make debug TC=otbn_smoke_test

# 指定种子打开对应波形
make debug TC=otbn_smoke_test SEED=12345
```

---

## 清理

```bash
# 清理本项目输出
make clean

# 清理所有项目输出
make clean_all
```

---

## 目录结构

```
verif/otbn/
├── Makefile                        # 模块级 Makefile（委托给 scripts/）
├── case_list.json                  # 回归用例列表
├── dut.flist                       # DUT 编译文件列表
├── tb.flist                        # TB 编译文件列表
├── tb/
│   ├── otbn_tl_if.sv              # TL-UL 虚拟接口
│   ├── otbn_tb_pkg.sv             # TB 顶层 package
│   └── tb_top.sv                  # TB 顶层模块
├── agent/
│   ├── otbn_tl_seq_item.sv        # TL-UL 事务 item
│   ├── otbn_tl_agent_cfg.sv       # Agent 配置
│   ├── otbn_tl_driver.sv          # TL-UL 驱动（a/d channel 握手）
│   ├── otbn_tl_monitor.sv         # TL-UL 监控（广播已完成事务）
│   ├── otbn_tl_agent.sv           # Agent 组装
│   └── otbn_tl_pkg.sv             # Agent package
├── env/
│   ├── otbn_env_cfg.sv            # 环境配置
│   ├── otbn_scoreboard.sv         # Scoreboard（总线错误/ERR_BITS/DMEM比对）
│   ├── otbn_env.sv                # 验证环境
│   └── otbn_env_pkg.sv            # 环境 package
├── seq/
│   ├── otbn_tb_base_seq.sv        # 基础序列（tl_write/read, load_imem, run_otbn…）
│   ├── otbn_smoke_seq.sv          # Smoke 序列
│   ├── otbn_dmem_rw_seq.sv        # DMEM 读写序列
│   └── otbn_vseq_list.sv          # 序列列表
├── test/
│   ├── otbn_base_test.sv          # 基础测试类
│   ├── otbn_smoke_test.sv         # Smoke 测试
│   ├── otbn_dmem_rw_test.sv       # DMEM 读写测试
│   └── otbn_test_pkg.sv           # 测试 package
└── verif_plan/
    ├── otbn_testplan.hjson         # 主验证计划（来自 OpenTitan）
    ├── otbn_sec_cm_testplan.hjson  # 安全对策验证计划
    ├── dv_overview.md              # DV 环境总览
    ├── fcov.md                     # 功能覆盖率规格
    └── *.yml                       # 指令集/寄存器定义
```

---

## 架构说明

### TL-UL 完整性
OTBN 通过 TL-UL 总线访问，RTL 内部会校验命令完整性（`cmd_intg`）。  
TB 在 VIF 和 DUT 之间插入了 `tlul_cmd_intg_gen` 模块，**自动计算并填充 `cmd_intg` 和 `data_intg`**，驱动端无需手动处理。

### 外部接口 Tie-off
| 接口         | 处理方式                                |
|--------------|-----------------------------------------|
| EDN (RND)    | `edn_ack = edn_req`，返回固定熵 `0xDEADBEEF` |
| EDN (URND)   | `edn_ack = edn_req`，返回固定熵 `0xCAFEBABE` |
| OTP Key      | 收到 `req` 后返回固定密钥（128-bit）   |
| LC Escalate  | 常驻 `LC_TX_DEFAULT`（不触发 escalate）|
| Alert        | `ack_n=1, ping_n=1`（无 alert 响应）   |
| Keymgr       | `valid=0`（不提供 sideload key）       |
