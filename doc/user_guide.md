# UVM_AI_DEMO 用户使用手册

> 适用对象：验证工程师
> EDA 工具：Synopsys VCS 2020 + Verdi

---

## 目录

1. [快速上手](#1-快速上手)
2. [目录结构](#2-目录结构)
3. [环境初始化](#3-环境初始化)
4. [新建验证项目](#4-新建验证项目)
5. [编译](#5-编译)
6. [仿真运行](#6-仿真运行)
7. [回归测试](#7-回归测试)
8. [波形调试](#8-波形调试)
9. [覆盖率](#9-覆盖率)
10. [回归报告](#10-回归报告)
11. [CI/CD 集成](#11-cicd-集成)
12. [变量速查表](#12-变量速查表)

---

## 1. 快速上手

```bash
# 第一步：初始化环境
source scripts/setup.sh

# 第二步：编译
cd scripts
make compile PROJ=example

# 第三步：运行单条测试
make run PROJ=example TC=write_test

# 第四步：批量回归
make regress PROJ=example TAG=smoke
```

---

## 2. 目录结构

```
UVM_AI_DEMO/
├── design/              # DUT（被测设计）RTL 代码
├── vip/                 # Verification IP
├── verif/               # 验证激励
│   └── <项目名>/
│       ├── dut.flist    # RTL 文件列表（必须）
│       ├── tb.flist     # Testbench 文件列表（可选）
│       └── case_list.json   # 激励管理文件（必须）
├── scripts/             # 自动化脚本
│   ├── Makefile         # 主入口
│   ├── setup.sh         # 环境初始化
│   ├── find_flist.sh    # 文件列表扫描
│   ├── vcs_compile.sh   # 编译封装
│   ├── vcs_run.sh       # 仿真封装
│   ├── vcs_debug.sh     # 波形调试封装
│   ├── run_cases.py     # 回归管理
│   ├── merge_cov.sh     # 覆盖率合并
│   └── gen_report.py    # 报告生成
├── doc/                 # 文档
├── output/              # 编译/仿真输出（自动生成，不提交）
├── Jenkinsfile          # Jenkins 流水线
└── .gitlab-ci.yml       # GitLab CI 配置
```

**输出目录结构**（自动生成）：

```
output/<项目名>/
├── compile/             # 编译产物（simv、日志）
├── sim/
│   └── <TC>_<seed>/     # 每条用例独立目录
│       ├── <TC>.log     # 仿真日志
│       ├── <TC>.fsdb    # 波形文件
│       └── result.json  # 仿真结果（供回归汇总使用）
├── reports/
│   └── <时间戳>/        # 每次回归独立报告目录
│       ├── report.html
│       ├── report.csv
│       └── results.json
├── cov_report/          # 覆盖率合并报告
│   ├── code_cov/
│   └── func_cov/
└── seed_record.csv      # 历史种子记录
```

---

## 3. 环境初始化

**必须使用 `source`，不可直接执行：**

```bash
source scripts/setup.sh
```

多站点环境切换：

```bash
source scripts/setup.sh --site site_a
```

**首次使用**请编辑 `scripts/setup.sh`，配置以下变量：

| 变量 | 说明 | 示例 |
|------|------|------|
| `VCS_HOME` | VCS 安装目录 | `/tools/synopsys/vcs/O-2018.09-SP2` |
| `VERDI_HOME` | Verdi 安装目录 | `/tools/synopsys/verdi/S-2021.09` |
| `SNPSLMD_LICENSE_FILE` | License 服务器 | `27020@license-server` |

> 也可通过 `make setup` 查看配置提示。

---

## 4. 新建验证项目

### 4.1 创建项目目录

```bash
mkdir -p verif/my_proj
```

### 4.2 编写 dut.flist

`verif/my_proj/dut.flist` 指定需要编译的 RTL 文件：

```
// RTL 文件列表（使用 ${REPO_ROOT} 表示仓库根目录）

// 头文件搜索路径
+incdir+${REPO_ROOT}/design/my_dut/rtl

// RTL 源文件（逐行列出）
${REPO_ROOT}/design/my_dut/rtl/my_dut_pkg.sv
${REPO_ROOT}/design/my_dut/rtl/my_dut.sv
```

`tb.flist`（可选）填写 Testbench 相关文件：

```
+incdir+${REPO_ROOT}/vip/my_vip
+incdir+${REPO_ROOT}/verif/my_proj

${REPO_ROOT}/vip/my_vip/my_vip_pkg.sv
${REPO_ROOT}/verif/my_proj/tb_top.sv
```

### 4.3 编写 case_list.json

`verif/my_proj/case_list.json` 维护所有验证激励：

```json
{
    "cases": [
        {
            "case_id":     "TC_001",
            "case_name":   "base_test",
            "case_tag":    ["smoke"],
            "case_seq":    "my_base_seq",
            "case_define": [],
            "case_timeout": 1800
        },
        {
            "case_id":     "TC_002",
            "case_name":   "write_test",
            "case_tag":    ["smoke", "write"],
            "case_seq":    "my_write_seq",
            "case_define": ["+DATA_WIDTH=32", "+BURST_LEN=4"],
            "case_timeout": 1800
        }
    ]
}
```

**字段说明：**

| 字段 | 必填 | 说明 |
|------|------|------|
| `case_id` | ✓ | 激励唯一 ID，建议全局唯一 |
| `case_name` | ✓ | 激励名称，对应 UVM test 类名（`+UVM_TESTNAME`）|
| `case_tag` | ✓ | 标签列表，用于过滤。建议定义 `smoke`（冒烟）、`regress`（回归）等 |
| `case_seq` | ✓ | 对应的 UVM sequence 类名，通过 `+UVM_SEQ` 传递给 TB |
| `case_define` | 可选 | 仿真时传入的 plusarg 列表，如 `["+WIDTH=32"]` |
| `case_timeout` | 可选 | 单条激励超时秒数，覆盖全局默认值（3600s）|

---

## 5. 编译

```bash
cd scripts

# 基本编译
make compile PROJ=my_proj

# 开启代码覆盖率编译
make compile PROJ=my_proj CODE_COV=1
```

编译产物位于 `output/my_proj/compile/`，日志为 `vcs_compile.log`。

---

## 6. 仿真运行

### 6.1 单条测试

```bash
# 运行指定测试
make run PROJ=my_proj TC=write_test

# 指定种子
make run PROJ=my_proj TC=write_test SEED=12345

# 不转储波形（加快速度）
make run PROJ=my_proj TC=write_test WAVE=0

# 运行完自动打开 Verdi
make run PROJ=my_proj TC=write_test WAVE=1 AUTO_DEBUG=1

# 限制波形范围（减小 FSDB 文件大小）
make run PROJ=my_proj TC=write_test WAVE_SCOPE=tb_top.u_dut
```

### 6.2 编译 + 运行一步完成

```bash
make all PROJ=my_proj TC=write_test SEED=12345
```

---

## 7. 回归测试

### 7.1 运行全部激励

```bash
make regress PROJ=my_proj
```

### 7.2 过滤激励

```bash
# 按 tag 过滤（多个 tag 取并集）
make regress PROJ=my_proj TAG=smoke
make regress PROJ=my_proj "TAG=smoke write"

# 按 case_id 过滤
make regress PROJ=my_proj "CASE_ID=TC_001 TC_003"

# 按 case_name 精确过滤
make regress PROJ=my_proj CASE_NAME=write_test

# 按正则表达式过滤 case_name
make regress PROJ=my_proj CASE_REGEX='write.*test'
make regress PROJ=my_proj "CASE_REGEX=^TC_00[12]"
```

### 7.3 并行加速

```bash
# 本地 4 并行
make regress PROJ=my_proj TAG=smoke JOBS=4

# 提交到 LSF 集群
make regress PROJ=my_proj JOBS=8 SUBMIT=lsf

# 提交到 SGE 集群
make regress PROJ=my_proj SUBMIT=sge
```

> **LSF 资源配置**：通过环境变量 `LSF_ARGS` 设置，例如：
> ```bash
> export LSF_ARGS="-q normal -n 1 -R 'rusage[mem=8192]'"
> ```

### 7.4 重跑失败激励

```bash
# 重跑上次回归中失败的激励（保留原种子，便于复现）
make rerun PROJ=my_proj
```

### 7.5 直接调用 Python 脚本

```bash
python3 scripts/run_cases.py \
    --proj my_proj \
    --tag smoke write \
    --jobs 4 \
    --wave \
    --code_cov \
    --dry_run       # 仅打印，不执行
```

---

## 8. 波形调试

```bash
# 打开最新一次仿真的波形
make debug PROJ=my_proj TC=write_test

# 指定种子（精确定位某次仿真）
make debug PROJ=my_proj TC=write_test SEED=12345
```

脚本优先使用 **Verdi**，若未找到则回退到 **DVE**。

---

## 9. 覆盖率

### 9.1 运行时开启

```bash
# 代码覆盖率（line / condition / fsm / toggle / branch）
make regress PROJ=my_proj CODE_COV=1

# 功能覆盖率（UVM covergroup，需 TB 中使用 +FUNC_COV plusarg 控制）
make regress PROJ=my_proj FUNC_COV=1

# 同时开启
make regress PROJ=my_proj CODE_COV=1 FUNC_COV=1
```

### 9.2 合并并生成报告

回归结束后执行：

```bash
make merge_cov PROJ=my_proj
```

报告位于：
- 代码覆盖率：`output/my_proj/cov_report/code_cov/dashboard.html`
- 功能覆盖率：`output/my_proj/cov_report/func_cov/dashboard.html`

---

## 10. 回归报告

每次回归结束后自动生成 HTML + CSV 报告，位于：

```
output/<项目名>/reports/<时间戳>/
├── report.html    # 可视化报告（含 PASS/FAIL 统计、种子、耗时）
├── report.csv     # 结构化数据（可导入 Excel）
└── results.json   # 原始结果数据
```

也可以从历史结果重新生成报告：

```bash
make report PROJ=my_proj
```

---

## 11. CI/CD 集成

### Jenkins

仓库根目录已提供 `Jenkinsfile`，支持参数化构建：

| 参数 | 说明 |
|------|------|
| `PROJ` | 项目名称 |
| `TAG` | 回归过滤标签（空=全量）|
| `JOBS` | 并行作业数 |
| `CODE_COV` | 开启代码覆盖率 |
| `FUNC_COV` | 开启功能覆盖率 |
| `SUBMIT` | 提交方式（local/lsf/sge）|
| `FULL_REGRESS` | 是否执行全量回归（默认仅 smoke）|

### GitLab CI

`.gitlab-ci.yml` 已配置，push 代码时自动触发 smoke 测试，每天凌晨 2 点执行全量回归。

---

## 12. 变量速查表

### 仿真控制

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PROJ` | 无（必填）| 项目名称，对应 `verif/` 下的子目录 |
| `TC` | `base_test` | UVM 测试类名（`make run/all` 使用）|
| `SEED` | `random` | 随机种子，`random` 表示自动生成 |
| `VERBOSITY` | `UVM_MEDIUM` | UVM 打印级别 |
| `WAVE` | `1` | `1`=转储 FSDB 波形，`0`=不转储 |
| `WAVE_SCOPE` | 空（全量）| 波形转储范围，如 `tb_top.u_dut` |
| `CODE_COV` | `0` | `1`=开启代码覆盖率 |
| `FUNC_COV` | `0` | `1`=开启功能覆盖率 |
| `CASE_TIMEOUT` | `3600` | 单条激励超时秒数 |
| `AUTO_DEBUG` | `0` | `1`=仿真结束后自动打开波形 |

### 回归控制

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `JOBS` | `1` | 本地并行作业数 |
| `SUBMIT` | `local` | 提交方式：`local` / `lsf` / `sge` |
| `TAG` | 空 | 按 `case_tag` 过滤，多值空格分隔 |
| `CASE_ID` | 空 | 按 `case_id` 精确过滤 |
| `CASE_NAME` | 空 | 按 `case_name` 精确过滤 |
| `CASE_REGEX` | 空 | 按正则表达式匹配 `case_name` |

### 常用命令速查

```bash
make compile   PROJ=<proj>                          # 编译
make run       PROJ=<proj> TC=<tc>                  # 单条仿真
make all       PROJ=<proj> TC=<tc>                  # 编译+仿真
make regress   PROJ=<proj> [TAG=<tag>] [JOBS=N]    # 批量回归
make rerun     PROJ=<proj>                          # 重跑失败激励
make debug     PROJ=<proj> TC=<tc>                  # 波形调试
make merge_cov PROJ=<proj>                          # 合并覆盖率
make report    PROJ=<proj>                          # 生成回归报告
make clean     PROJ=<proj>                          # 清理项目输出
make clean_all                                      # 清理所有输出
make help                                           # 显示帮助
make setup                                          # 环境配置说明
```
