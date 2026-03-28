# UVM_AI_DEMO 框架维护手册

> 适用对象：框架维护者、基础设施工程师
> 本文档以需求树形结构组织，描述每项特性的设计思路与代码实现。

---

## 特性全景树

```
UVM_AI_DEMO 验证框架
├── 1. 环境管理
│   └── 1.1 EDA 环境初始化（setup.sh）
├── 2. 编译流程
│   ├── 2.1 文件列表自动扫描（find_flist.sh）
│   └── 2.2 VCS 编译封装（vcs_compile.sh）
├── 3. 仿真运行
│   ├── 3.1 单条仿真封装（vcs_run.sh）
│   ├── 3.2 超时控制
│   ├── 3.3 波形转储（FSDB）与范围控制
│   └── 3.4 仿真结果记录（result.json）
├── 4. 激励管理
│   ├── 4.1 JSON 格式激励定义（case_list.json）
│   ├── 4.2 激励解析（CaseParser）
│   └── 4.3 激励过滤（CaseFilter）
│       ├── 按 tag 过滤
│       ├── 按 case_id 过滤
│       ├── 按 case_name 精确过滤
│       └── 按正则表达式过滤
├── 5. 回归执行
│   ├── 5.1 本地顺序/并行执行（LocalRunner）
│   ├── 5.2 LSF 集群提交（LsfRunner）
│   ├── 5.3 SGE 集群提交（SgeRunner）
│   └── 5.4 回归会话管理（RegressionSession）
├── 6. 覆盖率
│   ├── 6.1 代码覆盖率（CODE_COV）
│   ├── 6.2 功能覆盖率（FUNC_COV）
│   └── 6.3 覆盖率合并与报告（merge_cov.sh）
├── 7. 报告与记录
│   ├── 7.1 种子记录与失败重现（SeedRecorder / --rerun）
│   └── 7.2 回归报告生成（gen_report.py）
│       ├── HTML 报告（HtmlReportGenerator）
│       └── CSV 报告（CsvReportGenerator）
├── 8. 波形调试
│   ├── 8.1 Verdi/DVE 自动启动（vcs_debug.sh）
│   └── 8.2 仿真后自动打开波形（AUTO_DEBUG）
└── 9. CI/CD 集成
    ├── 9.1 Jenkins 流水线（Jenkinsfile）
    └── 9.2 GitLab CI（.gitlab-ci.yml）
```

---

## 1. 环境管理

### 1.1 EDA 环境初始化

**文件**：`scripts/setup.sh`

**设计思路**：

验证环境对工具路径、License 高度依赖，不同服务器/站点配置各异。`setup.sh` 作为统一入口，将环境配置集中管理，使用者只需 `source` 一次即可对齐环境，避免在每个脚本中分散配置。

**实现要点**：

- 使用 `BASH_SOURCE` 检测是否被 `source` 调用，防止直接执行导致环境变量无法生效
- 通过 `--site` 参数支持多站点配置，使用 `case` 语句切换，扩展新站点只需添加一个分支
- 调用 `command -v` 检查工具可用性并打印结果，快速定位配置问题
- 自动推导 `REPO_ROOT`（脚本位置的上一级），后续所有脚本通过此变量构建路径

```bash
# 防止直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 1; fi

# 多站点配置
case "${_SITE}" in
    default) export VCS_HOME="/tools/..."  ;;
    site_a)  export VCS_HOME="/eda/..."    ;;
esac
```

**扩展方式**：在 `case` 语句中添加新站点分支即可。

---

## 2. 编译流程

### 2.1 文件列表自动扫描

**文件**：`scripts/find_flist.sh`

**设计思路**：

每个验证项目维护自己的 `dut.flist`，包含该项目需要编译的 RTL 文件。编译前需要将文件列表中的路径变量（`${REPO_ROOT}`）展开为绝对路径，避免 VCS 因工作目录不同导致找不到文件。

**实现要点**：

- 接受 `PROJ` 环境变量，在 `verif/${PROJ}/` 下查找 `dut.flist`
- 使用 `sed` 将 `${REPO_ROOT}` 展开为绝对路径，生成 `merged.flist`
- 若项目存在 `tb.flist`，将其内容合并追加到同一 `merged.flist`
- 项目不存在时，自动列出所有可用项目（`find verif/ -name "dut.flist"`），便于排查错误

```bash
# 展开变量
resolved=$(echo "$line" | sed "s|\${REPO_ROOT}|${REPO_ROOT}|g")
```

### 2.2 VCS 编译封装

**文件**：`scripts/vcs_compile.sh`

**设计思路**：

将 VCS 复杂的编译命令封装为脚本，通过环境变量控制条件编译选项，保持 Makefile 简洁。

**关键编译标志**：

| 标志 | 作用 |
|------|------|
| `-full64` | 64 位模式 |
| `-sverilog` | 启用 SystemVerilog |
| `-ntb_opts uvm-1.2` | 使用 VCS 内置 UVM 1.2，无需手动指定 `$UVM_HOME` |
| `-debug_access+all` | 开启完整调试（`WAVE=1` 时）|
| `-kdb` | 生成 Verdi KDB 数据库 |
| `-cm line+cond+fsm+tgl+branch` | 代码覆盖率（`CODE_COV=1` 时）|

**实现要点**：

- 编译命令通过字符串拼接构建，`if` 语句按需追加条件选项
- 编译输出目录固定为 `output/${PROJ}/compile/`，日志与中间文件均在此处
- 编译完成后检查 `simv` 是否生成，作为编译成功的判断依据

---

## 3. 仿真运行

### 3.1 单条仿真封装

**文件**：`scripts/vcs_run.sh`

**设计思路**：

`vcs_run.sh` 是仿真的核心执行单元，所有运行参数通过环境变量传入，使其既可被 Makefile 直接调用，也可被 `run_cases.py` 批量调用（每次调用独立传入不同的环境变量）。

**仿真输出目录隔离**：

每条用例按 `output/${PROJ}/sim/${TC}_${SEED}/` 存放，确保并行运行时不同用例的输出不互相覆盖。

### 3.2 超时控制

**设计思路**：

仿真挂死是回归中常见问题，会阻塞整个流程。使用系统 `timeout` 命令包裹 `simv` 执行，`timeout` 返回码 `124` 表示超时。

```bash
timeout "${CASE_TIMEOUT}" bash -c "${SIM_CMD}"
SIM_EXIT=$?
if [ "${SIM_EXIT}" -eq 124 ]; then TIMED_OUT=1; fi
```

**超时优先级**：`case_list.json` 中的 `case_timeout` 字段 > 全局 `CASE_TIMEOUT` 变量（默认 3600s）。优先级在 `run_cases.py` 的 `_build_env()` 中实现：

```python
timeout = case.get("case_timeout") or self.args.timeout
env["CASE_TIMEOUT"] = str(timeout)
```

### 3.3 波形转储与范围控制

**设计思路**：

全量波形（`+all`）对于大型 SOC 设计会产生数十 GB 的 FSDB 文件，严重影响存储和 IO。引入 `WAVE_SCOPE` 变量，非空时通过 `+WAVE_SCOPE` plusarg 传递给 TB，由 TB 中的 `fsdbDumpvars` 调用决定实际转储范围。

```bash
if [ -n "${WAVE_SCOPE}" ]; then
    SIM_CMD+=" +WAVE_SCOPE=${WAVE_SCOPE}"
fi
```

### 3.4 仿真结果记录

**设计思路**：

并行或集群运行时，`run_cases.py` 无法实时捕获每个 `vcs_run.sh` 进程的输出，需要一种机制让各进程将结果写入文件，主进程稍后读取汇总。

每次仿真结束后，`vcs_run.sh` 用 Python 内联代码写入 `result.json`：

```bash
python3 - <<EOF
import json, datetime
result = {
    "case_name": "${TC}", "seed": ${SEED},
    "passed": ${PASSED} == 1,
    "uvm_fatal": ${UVM_FATAL}, "duration": ${DURATION},
    ...
}
with open("${RESULT_JSON}", "w") as f:
    json.dump(result, f, indent=2)
EOF
```

`run_cases.py` 的 `_read_result_json()` 读取该文件；若文件不存在（脚本异常退出），则以 `passed=False` 作为 fallback。

---

## 4. 激励管理

### 4.1 JSON 格式激励定义

**文件**：`verif/<项目名>/case_list.json`

**设计思路**：

用结构化的 JSON 文件代替手动维护的用例列表，便于版本控制、代码审查和程序解析。JSON 选择 `cases` 作为顶层数组，预留顶层字段扩展空间（如后续可加 `meta`、`version` 等）。

### 4.2 激励解析（CaseParser）

**文件**：`scripts/run_cases.py` — `CaseParser` 类

**设计思路**：

将字段解析逻辑集中在 `_parse_case()` 一个方法中，新增字段时只需在此处添加一行，调用方无感知。

```python
def _parse_case(self, raw: dict, idx: int) -> dict:
    case["case_id"]      = str(raw["case_id"])
    case["case_define"]  = list(raw.get("case_define", []))
    case["case_timeout"] = int(raw.get("case_timeout", 0))
    # 扩展新字段：
    # case["case_priority"] = str(raw.get("case_priority", "normal"))
    return case
```

**扩展规则**：
1. 必填字段加入 `REQUIRED_FIELDS` 列表，可选字段使用 `raw.get("字段名", 默认值)`
2. 字段类型显式转换（`str()`/`int()`/`list()`），防止 JSON 类型不一致引起的运行时错误

### 4.3 激励过滤（CaseFilter）

**文件**：`scripts/run_cases.py` — `CaseFilter` 类

**过滤逻辑**：多个条件同时指定时**取交集**；单个条件内多值**取并集**。

```
TAG=smoke write  →  匹配 tag 包含 smoke 或 write 的用例（并集）
TAG=smoke + CASE_REGEX=write.*  →  先过滤 smoke，再从结果中匹配正则（交集）
```

**正则过滤实现**：使用 `re.compile(pattern).search(case_name)`，支持部分匹配；若正则非法，给出明确错误信息后退出。

---

## 5. 回归执行

### 5.1 本地顺序/并行执行（LocalRunner）

**文件**：`scripts/run_cases.py` — `LocalRunner` 类

**设计思路**：

使用 `concurrent.futures.ThreadPoolExecutor` 实现并行。由于每条用例是独立的 `subprocess`（子进程），Python GIL 不影响并行效果，`ThreadPoolExecutor` 比 `ProcessPoolExecutor` 更轻量。

```python
with ThreadPoolExecutor(max_workers=jobs) as executor:
    future_map = {executor.submit(self._run_one, c, ...): i
                  for i, c in enumerate(cases)}
    for future in as_completed(future_map):
        results[future_map[future]] = future.result()
```

### 5.2 LSF 集群提交（LsfRunner）

**文件**：`scripts/run_cases.py` — `LsfRunner` 类

**设计思路**：

SOC 验证环境通常有数百条用例，本地并行资源有限，需借助 LSF/SGE 集群。`LsfRunner` 的流程分三步：

1. **提交**：为每条激励构建独立的 `bsub` 命令，从输出中解析 Job ID（正则 `Job <(\d+)>`）
2. **等待**：每 30 秒调用 `bjobs -noheader` 轮询作业状态，判断 `RUN/PEND` 的作业集合是否为空
3. **收集**：作业完成后，从各自的 `result.json` 读取结果

LSF 资源参数通过环境变量 `LSF_ARGS` 传入，不硬编码在脚本中，便于适配不同集群配置。

### 5.3 SGE 集群提交（SgeRunner）

**文件**：`scripts/run_cases.py` — `SgeRunner` 类

结构与 `LsfRunner` 完全一致，差异仅在提交命令（`qsub`）和状态轮询命令（`qstat`）。两者共享相同的"提交-等待-收集"模式。

### 5.4 回归会话管理（RegressionSession）

**文件**：`scripts/run_cases.py` — `RegressionSession` 类

**设计思路**：

将一次完整回归的各步骤（选择运行器、执行、记录种子、生成报告）封装为一个会话对象，使主流程 `main()` 保持简洁：

```python
session = RegressionSession(args, base_env)
ok = session.run(matched_cases)
```

报告目录按时间戳命名（`output/PROJ/reports/YYYYMMDD_HHMMSS/`），保留历史记录，不覆盖。

---

## 6. 覆盖率

### 6.1 代码覆盖率（CODE_COV）

**编译阶段**：`vcs_compile.sh` 在 `CODE_COV=1` 时追加：
```bash
-debug_access+all -cm line+cond+fsm+tgl+branch
```

**仿真阶段**：`vcs_run.sh` 在 `CODE_COV=1` 时追加：
```bash
-cm line+cond+fsm+tgl+branch
-cm_dir ${SIM_DIR}/code_cov.vdb
-cm_name ${TC}_${SEED}          # 用于合并时区分各实例
```

每条用例产生独立的 `.vdb` 目录，合并时使用 `urg -dir` 指定多个。

### 6.2 功能覆盖率（FUNC_COV）

仿真时注入 `+FUNC_COV` plusarg，Testbench 通过 `$test$plusargs("FUNC_COV")` 判断是否使能 covergroup 采样。设计上不依赖编译时宏，保持单次编译可同时运行有/无功能覆盖率的用例。

### 6.3 覆盖率合并与报告

**文件**：`scripts/merge_cov.sh`

**实现要点**：
- 使用 `find ... -name "*.vdb" -type d` 收集所有仿真产生的覆盖率数据
- 调用 `urg -dir <vdb1> -dir <vdb2> ... -format both -report <输出目录>` 合并
- 代码覆盖率（`-metric line+...`）和功能覆盖率（`-metric group`）分别生成独立报告

---

## 7. 报告与记录

### 7.1 种子记录与失败重现

**文件**：`scripts/gen_report.py` — `SeedRecorder` 类；`scripts/run_cases.py` — `--rerun` 模式

**种子记录格式**（`output/<proj>/seed_record.csv`）：

```
case_id, case_name, seed, result, timestamp, log
TC_001, write_test, 12345, FAIL, 2026-03-28 13:00:00, /path/to/sim.log
```

**追加写入**：每次回归结束后，`RegressionSession._record_seeds()` 调用 `SeedRecorder.append()` 追加写入，保留完整历史。

**重跑逻辑**（`--rerun`）：

1. `SeedRecorder.get_failed_cases()` 读取 CSV，按 `case_id` 去重保留最新一条，筛选 `result=FAIL` 的记录
2. 从 `case_list.json` 中查找对应用例的完整信息
3. 将历史种子注入 `args.seed`，以该种子重新运行，确保完全复现失败场景

### 7.2 回归报告生成

**文件**：`scripts/gen_report.py`

**三个类职责分离**：

| 类 | 职责 |
|----|------|
| `HtmlReportGenerator` | 生成带样式的 HTML 报告，PASS 行绿色、FAIL 行红色 |
| `CsvReportGenerator` | 生成标准 CSV，字段固定，便于外部工具处理 |
| `SeedRecorder` | 种子追加记录与查询（与报告解耦，单独使用）|

**HTML 报告结构**：顶部摘要卡片（总计/PASS/FAIL/通过率）+ 详细用例表格（含日志链接）。全部使用内联 CSS，无外部依赖，便于在无网络的内网环境打开。

**集成方式**：`run_cases.py` 通过 `sys.path.insert` 导入 `gen_report.py` 中的类，使两者既可联动也可独立使用：

```python
# run_cases.py 中
from gen_report import HtmlReportGenerator, CsvReportGenerator, SeedRecorder
```

---

## 8. 波形调试

### 8.1 Verdi/DVE 自动启动

**文件**：`scripts/vcs_debug.sh`

**工具选择逻辑**：使用 `command -v verdi` 检查可用性，优先 Verdi，其次 DVE，均无则报错。工具在后台启动（`&`），不阻塞终端。

**FSDB 查找策略**：
1. 若指定 `SEED`，精确定位 `sim/${TC}_${SEED}/${TC}.fsdb`
2. 若 `SEED=random`，`find + xargs ls -t | head -1` 取最新的同名 FSDB

### 8.2 仿真后自动打开波形（AUTO_DEBUG）

`vcs_run.sh` 末尾判断：`AUTO_DEBUG=1` 且 `WAVE=1` 且 FSDB 文件存在，则调用 `vcs_debug.sh`。设计上将判断放在仿真完成之后，确保不影响仿真本身的返回码。

---

## 9. CI/CD 集成

### 9.1 Jenkins 流水线

**文件**：`Jenkinsfile`

**流水线阶段**：`Checkout → Setup → Compile → Smoke → Full Regress（可选）→ Report`

**关键设计决策**：
- `Full Regress` 阶段使用 `when { expression { return params.FULL_REGRESS } }` 控制，默认不执行，由人工触发，避免每次提交都跑全量回归
- 报告归档使用 `archiveArtifacts`，HTML 报告通过 HTML Publisher 插件在 Jenkins 界面直接查看
- `cleanWs(cleanWhenSuccess: false)` 确保失败时保留工作空间便于调试

### 9.2 GitLab CI

**文件**：`.gitlab-ci.yml`

**触发策略**：
- `push` 触发：仅运行 `smoke` 阶段（快速反馈）
- 定时触发：每天凌晨 2 点执行全量回归（`only: schedules`）

---

## 扩展指南

### 新增 JSON 字段

1. 在 `verif/<proj>/case_list.json` 中添加字段
2. 在 `CaseParser._parse_case()` 中添加解析：

```python
case["case_priority"] = str(raw.get("case_priority", "normal"))
```

3. 在 `LocalRunner._build_env()` 中将字段注入环境变量（如需传给 Shell 脚本）：

```python
env["CASE_PRIORITY"] = case.get("case_priority", "normal")
```

### 新增集群类型

参考 `LsfRunner` 实现新的 Runner 类，继承相同的"提交-等待-收集"接口：

```python
class NewClusterRunner:
    def run_all(self, cases: list[dict]) -> list[dict]: ...
    def _submit_job(self, case, env): ...
    def _wait_for_jobs(self, job_ids): ...
```

在 `RegressionSession._get_runner()` 中注册：

```python
elif submit == "new_cluster":
    return NewClusterRunner(...)
```

### 新增过滤维度

在 `CaseFilter.filter()` 中添加新参数，以及 `parse_args()` 中添加对应的 `--new_filter` 参数，Makefile 中同步添加变量即可。
