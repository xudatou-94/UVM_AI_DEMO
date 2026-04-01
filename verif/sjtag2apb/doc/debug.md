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
