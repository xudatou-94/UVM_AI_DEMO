# sjtag2apb 调试记录

---

## 问题一：vcs_compile.sh 覆盖率开关变量错误

**文件**：`scripts/vcs_compile.sh`

**错误现象**：  
编译时覆盖率相关代码使用了未定义的 `COV` 环境变量，导致编译失败。

**根因**：  
Makefile 中覆盖率分为 `CODE_COV`（代码覆盖率）和 `FUNC_COV`（功能覆盖率）两个独立开关，但 `vcs_compile.sh` 中统一使用了 `COV`，与 Makefile 传入的变量名不匹配。

**修复**：  
将原来的单一 `COV` 判断拆分为两个独立分支：

```bash
# 修复前
if [ "${COV}" = "1" ]; then
    VCS_CMD+=" -cm line+cond+fsm+tgl+branch"
    VCS_CMD+=" -cm_dir ${COMPILE_DIR}/coverage"
fi

# 修复后
if [ "${CODE_COV}" = "1" ]; then
    VCS_CMD+=" -cm line+cond+fsm+tgl+branch"
    VCS_CMD+=" -cm_dir ${COMPILE_DIR}/coverage"
fi
if [ "${FUNC_COV}" = "1" ]; then
    VCS_CMD+=" -ntb_opts cover"
fi
```

---

## 问题二：apb_if.sv 中使用了 UVM 宏

**文件**：`vip/apb/apb_if.sv`

**错误信息**：
```
error-[IND] Identifier not declared
/vip/apb/apb_if.sv, 123
  Identifier 'UVM_NONE' has not been declared yet.
```

**根因**：  
Interface 文件在 `package` 之外单独编译，无法 `import uvm_pkg`，因此 `` `uvm_error `` 等 UVM 宏在 interface 中不可用。

**修复**：  
将 SVA assertion 的 else 分支中的 `` `uvm_error `` 替换为标准 SystemVerilog 的 `$error`：

```systemverilog
// 修复前
assert property (p_setup_penable)
  else `uvm_error("APB_IF", "APB 违例：SETUP 阶段 PENABLE 不为 0")

// 修复后
assert property (p_setup_penable)
  else $error("APB_IF: APB 违例：SETUP 阶段 PENABLE 不为 0");
```

三处 SVA（`p_setup_penable`、`p_access_penable`、`p_addr_stable`）均做了相同修改。

---

## 问题三：tb_pkg 中 include 顺序错误

**文件**：`verif/sjtag2apb/tb/sjtag2apb_tb_pkg.sv`

**错误信息**：
```
Error-[SV-URT] Undefined Reference to Type
sjtag2apb_base_test.sv, 62
  'sjtag2apb_tb_base_seq' is used as a type but never defined.
```

**根因**：  
`sjtag2apb_base_test.sv` 中使用了 `sjtag2apb_tb_base_seq` 类型，但在 pkg 中 `base_test` 的 `include` 排在 `tb_base_seq` 之前，编译时类型尚未定义。

**修复**：  
将 `seq/sjtag2apb_tb_base_seq.sv` 的 include 移至 `sjtag2apb_base_test.sv` 之前。

---

## 问题四：seq 文件中的语法错误（void' 和非法十六进制字符）

**文件**：`verif/sjtag2apb/tb/seq/sjtag2apb_tap_hard_reset_seq.sv`、`sjtag2apb_apb_slverr_seq.sv`、`sjtag2apb_random_regression_seq.sv`

**错误信息**：
```
Error-[SE] Syntax error
sjtag2apb_tap_hard_reset_seq.sv, 39: token is ''
Error-[SE] Syntax error
sjtag2apb_apb_slverr_seq.sv, 29: token is 'TA'
Error-[SE] Syntax error
sjtag2apb_random_regression_seq.sv, 31: token is 'RR0_0000'
```

**根因**：  
- `void'(1)` 为无意义占位语句，且引号字符存在编码问题，VCS 无法识别。  
- `32'hBAD_DATA`、`32'hERR0_0000` 中含有非十六进制字符（`T`、`R`），SystemVerilog 十六进制字面量只允许 `0-9` 和 `A-F`。

**修复**：  
- 删除 `void'(1)` 语句，注释保留说明意图。  
- `32'hBAD_DATA` → `32'hBAD_0000`，`32'hERR0_0000` → `32'hEE00_0000`。

---

## 问题五：uvm_subscriber::write() 参数名不匹配

**文件**：`verif/sjtag2apb/tb/sjtag2apb_coverage.sv`

**错误信息**：
```
Warning-[SV-ANDNMD] Argument names do not match
sjtag2apb_coverage.sv, 155
  The argument name 'item' for 'uvm_subscriber::write' in the derived class
  does not match argument 't' in the base class.
```

**根因**：  
`uvm_subscriber` 基类的 `write()` 函数参数名为 `t`，派生类覆写时使用了 `item`，VCS 严格检查参数名一致性。

**修复**：  
将派生类 `write(apb_seq_item item)` 改为 `write(apb_seq_item t)`，函数体内同步替换。

---

## 问题六：Makefile 变量值含尾部空格

**文件**：`scripts/Makefile`

**错误信息**：
```
timeout: invalid time interval '3600          '
```

**根因**：  
`CASE_TIMEOUT?= 3600          # 注释` 中注释前的空格被一并赋入变量值，传给 shell `timeout` 命令时参数变为 `'3600          '`，导致解析失败。

**修复**：  
将行内注释移到单独一行，避免空格污染变量值：

```makefile
# 修复前
CASE_TIMEOUT?= 3600          # 单条激励超时秒数

# 修复后
# 单条激励超时秒数（默认 1 小时）
CASE_TIMEOUT?= 3600
```

---

## 问题七：run_test() 未在时间 0 调用

**文件**：`verif/sjtag2apb/tb/tb_top.sv`

**错误信息**：
```
UVM_FATAL @ 650000: [RUNPHSTIME] The run phase must start at time 0,
current time is 650000.
```

**根因**：  
`tb_top.sv` 的 `initial` 块中，复位序列（`repeat(10) @(posedge pclk)` 等）在 `run_test()` 之前执行，消耗了仿真时间，导致 `run_test()` 在非零时刻被调用。UVM 强制要求 `run_test()` 在时间 0 调用。

**修复**：  
将复位序列拆到独立的 `initial` 块中与 UVM 并行运行，`run_test()` 所在的 `initial` 块只执行不消耗时间的操作（plusarg 读取、config_db 设置）：

```systemverilog
// 复位序列（独立 initial）
initial begin
  trst_n = 0; presetn = 0;
  repeat(10) @(posedge pclk); presetn = 1;
  repeat(5)  @(posedge tck);  trst_n  = 1;
  @(posedge tck);
end

// UVM 启动（时间 0）
initial begin
  // config_db 设置...
  run_test();  // 时间 0 调用
end
```

---

## 问题八：sjtag_driver 响应 item 的 sequence_id 为空

**文件**：`vip/sjtag/sjtag_driver.sv`

**错误信息**：
```
UVM_FATAL @ 900000: uvm_test_top.env.sjtag_agt.seqr [SQRPUT]
Driver put a response with null sequence_id
```

**根因**：  
driver 创建响应 item 后调用 `rsp.copy(req)`，`copy()` 只复制用户定义字段，不复制 UVM 框架内部的 `sequence_id` 和 `transaction_id`。调用 `item_done(rsp)` 时 sequencer 找不到对应的 sequence，触发 FATAL。

**修复**：  
将 `rsp.copy(req)` 替换为 `rsp.set_id_info(req)`，该接口专门用于将 request 的 ID 信息传递给 response：

```systemverilog
// 修复前
rsp.copy(req);

// 修复后
rsp.set_id_info(req);
```

---

## 问题九：`uvm_analysis_imp_decl` 置于类体内导致 write 回调不执行

**文件**：`verif/sjtag2apb/tb/sjtag2apb_scoreboard.sv`、`sjtag2apb_coverage.sv`、`sjtag2apb_tb_pkg.sv`

**现象**：  
`sjtag2apb_scoreboard` 的 `write_apb` 回调函数未被调用，scoreboard 无任何比对输出。

**根因**：  
`uvm_analysis_imp_decl(_suffix)` 宏展开时会定义一个新的类 `uvm_analysis_imp_<suffix>`，该类必须在 **package 作用域**定义，放在类体内无法被同包其他类正确识别。  
此外，`sjtag2apb_scoreboard` 和 `sjtag2apb_coverage` 均声明了 `uvm_analysis_imp_decl(_apb)`，在同一编译单元中重复定义同名类，导致类型冲突。

**修复**：  
将两个宏移至 `sjtag2apb_tb_pkg.sv` 的 package 顶部（所有类 include 之前），并从两个类体内删除：

```systemverilog
// sjtag2apb_tb_pkg.sv（package 顶部）
`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_sjtag)
```

---

## 问题十：apb_write_basic_seq 缺少回读，scoreboard 无法比对

**文件**：`verif/sjtag2apb/tb/seq/sjtag2apb_apb_write_basic_seq.sv`

**现象**：  
激励只执行写操作，scoreboard 的影子存储器记录了写入值，但没有读事务触发，无法做任何数据比对，测试实际无校验效果。

**修复**：  
改为两阶段执行：先完成全部 20 次写操作并记录地址/数据，再逐一回读，scoreboard 收到读事务时自动与影子存储器比对：

```systemverilog
// 第一阶段：写入
for (int i = 0; i < 20; i++) begin
  sjtag2apb_write(addr_list[i], wdata_list[i]);
end
// 第二阶段：回读（触发 scoreboard 比对）
for (int i = 0; i < 20; i++) begin
  sjtag2apb_read(addr_list[i], rdata);
end
```

---

## 问题十一：SEED=random 时 SIM_DIR 路径含尾部空格

**文件**：`scripts/vcs_run.sh`

**现象**：  
`SIM_DIR` 路径末尾含多余空格，导致基于 `SIM_DIR` 拼接的所有路径（日志、波形、result.json）均不合法，仿真目录创建失败。

**根因**：  
```bash
SEED=$((RANDOM * RANDOM))
```
bash 的 `RANDOM` 变量在算术展开时会附带隐式换行符，两次展开相乘后换行符残留在变量值中，拼入 `SIM_DIR` 后产生尾部空格。此外 `RANDOM`（0–32767）相乘易溢出 32 位有符号整数，产生负数种子。

**修复**：  
改用 `/dev/urandom` 生成 9 位纯数字字符串，再用 `$((10#...))` 去除前导零：

```bash
# 修复前
SEED=$((RANDOM * RANDOM))

# 修复后
SEED=$(tr -dc '0-9' < /dev/urandom | head -c 9)
SEED=$((10#${SEED}))  # 去除前导零，确保纯十进制整数
```

---

## 问题十二：SEED=random 尾部空格导致条件判断失败（Makefile 行内注释问题）

**文件**：`scripts/Makefile`、`scripts/vcs_run.sh`

**现象**：  
`SEED` 默认为 `random` 时，`vcs_run.sh` 中的条件判断始终不成立，`SEED_DIR` 未被正确生成，路径拼接仍然异常。

**根因**：  
Makefile 中变量赋值行带有行内注释：
```makefile
SEED        ?= random        # 随机种子，random 表示自动生成
```
注释前的空格被一并赋入变量值，`SEED` 实际为 `random        `（含尾部空格）。  
此外 `vcs_run.sh` 中使用的是单 `=` 的 `[ ]` 写法，在 `[[ ]]` 下推荐使用 `==`。

**修复**：

1. **Makefile**：将所有变量的行内注释统一移至上一行，彻底消除空格污染（影响 `TC`、`SEED`、`VERBOSITY`、`WAVE` 等所有变量）：
```makefile
# 随机种子，random 表示自动生成
SEED        ?= random
```

2. **vcs_run.sh**：`if` 判断改用 `[[ ]]` + `==`，同时对 `SEED` 做防御性 trim：
```bash
SEED="${SEED%% *}"          # trim 尾部空格
if [[ "${SEED}" == "random" ]]; then
    SEED_DIR=$(tr -dc '0-9' < /dev/urandom | head -c 9 | sed 's/^0*//')
    SEED_DIR="${SEED_DIR:-1}"
else
    SEED_DIR="${SEED}"
fi
```

---

## 问题十三：make run Error 141（SIGPIPE）

**文件**：`scripts/vcs_run.sh`

**错误信息**：
```
make[1]: *** [run] Error 141
```

**根因**：  
exit code 141 = 128 + 13（SIGPIPE）。`tr -dc '0-9' < /dev/urandom | head -c 9` 中 `head` 读够 9 字节后退出，`tr` 仍在向管道写入，收到 SIGPIPE 信号退出。脚本开头的 `set -euo pipefail` 将管道中任意命令的非零退出码视为脚本错误，触发 make 报 141。

**修复**：  
改用 `od` 直接从 `/dev/urandom` 读 4 字节转无符号十进制，无管道，不产生 SIGPIPE：
```bash
SEED_DIR=$(od -An -N4 -tu4 /dev/urandom | tr -d ' \n')
```

---

## 问题十四：FSDB 文件未生成 + vcs_debug.sh 路径与 vcs_run.sh 不一致

**文件**：`verif/sjtag2apb/tb/tb_top.sv`、`scripts/vcs_debug.sh`

**现象**：  
仿真运行后没有 FSDB 波形文件生成；`make debug` 报 "X is not a fsdb file"，且 `vcs_debug.sh` 在找不到 FSDB 时因 `xargs` 空输入问题可能意外拿到错误文件。

**根因**：  
1. `tb_top.sv` 缺少 `$fsdbDumpvars` 调用。`+fsdbfile+` plusarg 传入了 FSDB 路径，但 TB 从未调用 Novas 系统任务启动转储，仿真结束后不会生成任何波形文件。  
2. `vcs_debug.sh` 用 `${TC}_${SEED}` 拼接路径，而 `vcs_run.sh` 改用了 `${TC}_${SEED_DIR}`，两边不一致，导致精确路径匹配失败。  
3. `find ... | xargs ls -t` 当 `find` 结果为空时，`xargs` 会以无参数方式运行 `ls -t`，列出当前目录，可能返回无关文件。

**修复**：

1. **tb_top.sv**：增加 FSDB dump initial 块：
```systemverilog
initial begin
  string fsdb_file;
  if ($value$plusargs("fsdbfile+%s", fsdb_file)) begin
    $fsdbDumpfile(fsdb_file);
    $fsdbDumpvars(0, tb_top);
    $fsdbDumpSVA;
  end
end
```

2. **vcs_debug.sh**：改用 `SEED_DIR` 逻辑与 `vcs_run.sh` 保持一致，同时将 `find | xargs ls -t` 改为 `find | sort | tail -1` 消除空输入问题：
```bash
SEED="${SEED%% *}"
if [[ "${SEED}" != "random" ]]; then
    SEED_DIR="${SEED}"
    FSDB_FILE="${SIM_BASE}/${TC}_${SEED_DIR}/${TC}.fsdb"
fi
# 兜底：find 最新 fsdb（无 xargs）
if [ -z "${FSDB_FILE}" ] || [ ! -f "${FSDB_FILE}" ]; then
    FSDB_FILE=$(find "${SIM_BASE}" -name "${TC}.fsdb" -type f 2>/dev/null \
                | sort | tail -1)
fi
```
