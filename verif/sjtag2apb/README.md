# sjtag2apb 激励运行指南

## 目录结构

```
verif/sjtag2apb/
├── dut.flist               # 完整编译文件列表（RTL + VIP + TB）
├── case_list.json          # 用例列表（case_id / case_name / tags）
├── verif_plan/             # 功能点列表（feature_list.yaml）
└── tb/
    ├── tb_top.sv
    ├── sjtag2apb_tb_pkg.sv
    └── seq/                # 本目录：所有激励 sequence + test 类
```

## 前提条件

- 仿真器：VCS 2020.12+（支持 UVM 1.2）
- 环境变量：`REPO_ROOT` 指向仓库根目录

```bash
export REPO_ROOT=/path/to/UVM_AI_DEMO
```

---

## 编译命令

所有用例共用同一个编译步骤：

```bash
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    -f ${REPO_ROOT}/verif/sjtag2apb/dut.flist \
    -l compile.log \
    -o simv
```

---

## 运行命令

### 通用格式

```bash
./simv -l <case_name>.log \
       +UVM_TESTNAME=<test_class> \
       [+UVM_VERBOSITY=UVM_MEDIUM] \
       [+TCK_HALF_NS=<ns>] \
       [+TRANS_NUM=<n>]
```

**Plusarg 说明**

| Plusarg | 默认值 | 说明 |
|---|---|---|
| `+UVM_TESTNAME` | — | 必填，指定测试类名 |
| `+UVM_VERBOSITY` | `UVM_MEDIUM` | 日志详细程度 |
| `+TCK_HALF_NS` | `50`（10 MHz）| TCK 半周期，单位 ns |
| `+TRANS_NUM` | `50` | 随机回归用例事务数 |

---

## 各用例运行命令

| case_id | case_name | test_class | 运行命令 |
|---|---|---|---|
| sjtag2apb_0001 | tap_hard_reset | `sjtag2apb_tap_hard_reset_test` | 见下 |
| sjtag2apb_0002 | tap_soft_reset | `sjtag2apb_tap_soft_reset_test` | 见下 |
| sjtag2apb_0003 | idcode_read | `sjtag2apb_idcode_read_test` | 见下 |
| sjtag2apb_0004 | bypass | `sjtag2apb_bypass_test` | 见下 |
| sjtag2apb_0005 | apb_write_basic | `sjtag2apb_apb_write_basic_test` | 见下 |
| sjtag2apb_0006 | apb_write_burst | `sjtag2apb_apb_write_burst_test` | 见下 |
| sjtag2apb_0007 | apb_read_basic | `sjtag2apb_apb_read_basic_test` | 见下 |
| sjtag2apb_0008 | apb_read_after_write | `sjtag2apb_apb_read_after_write_test` | 见下 |
| sjtag2apb_0009 | apb_wait_state | `sjtag2apb_apb_wait_state_test` | 见下 |
| sjtag2apb_0010 | apb_slverr | `sjtag2apb_apb_slverr_test` | 见下 |
| sjtag2apb_0011 | cdc_freq_ratio | `sjtag2apb_cdc_freq_ratio_test` | 见下 |
| sjtag2apb_0012 | cdc_back2back | `sjtag2apb_cdc_back2back_test` | 见下 |
| sjtag2apb_0013 | random_regression | `sjtag2apb_random_regression_test` | 见下 |

```bash
# sjtag2apb_0001 - TAP 硬复位
./simv -l sjtag2apb_0001.log +UVM_TESTNAME=sjtag2apb_tap_hard_reset_test

# sjtag2apb_0002 - TAP 软复位
./simv -l sjtag2apb_0002.log +UVM_TESTNAME=sjtag2apb_tap_soft_reset_test

# sjtag2apb_0003 - IDCODE 读取
./simv -l sjtag2apb_0003.log +UVM_TESTNAME=sjtag2apb_idcode_read_test

# sjtag2apb_0004 - BYPASS 寄存器
./simv -l sjtag2apb_0004.log +UVM_TESTNAME=sjtag2apb_bypass_test

# sjtag2apb_0005 - APB 基本写
./simv -l sjtag2apb_0005.log +UVM_TESTNAME=sjtag2apb_apb_write_basic_test

# sjtag2apb_0006 - APB 突发写
./simv -l sjtag2apb_0006.log +UVM_TESTNAME=sjtag2apb_apb_write_burst_test

# sjtag2apb_0007 - APB 基本读
./simv -l sjtag2apb_0007.log +UVM_TESTNAME=sjtag2apb_apb_read_basic_test

# sjtag2apb_0008 - APB 先写后读
./simv -l sjtag2apb_0008.log +UVM_TESTNAME=sjtag2apb_apb_read_after_write_test

# sjtag2apb_0009 - APB 等待状态
./simv -l sjtag2apb_0009.log +UVM_TESTNAME=sjtag2apb_apb_wait_state_test

# sjtag2apb_0010 - APB PSLVERR 注入
./simv -l sjtag2apb_0010.log +UVM_TESTNAME=sjtag2apb_apb_slverr_test

# sjtag2apb_0011 - CDC 频率比验证（TCK=5MHz，PCLK=100MHz）
./simv -l sjtag2apb_0011.log +UVM_TESTNAME=sjtag2apb_cdc_freq_ratio_test +TCK_HALF_NS=100

# sjtag2apb_0012 - CDC 背靠背事务
./simv -l sjtag2apb_0012.log +UVM_TESTNAME=sjtag2apb_cdc_back2back_test

# sjtag2apb_0013 - 随机回归（100 条事务）
./simv -l sjtag2apb_0013.log +UVM_TESTNAME=sjtag2apb_random_regression_test \
       +UVM_VERBOSITY=UVM_LOW +TRANS_NUM=100
```

---

## 一键回归

运行全部 13 个用例并汇总结果：

```bash
#!/bin/bash
set -e
TESTS=(
  "sjtag2apb_0001 sjtag2apb_tap_hard_reset_test"
  "sjtag2apb_0002 sjtag2apb_tap_soft_reset_test"
  "sjtag2apb_0003 sjtag2apb_idcode_read_test"
  "sjtag2apb_0004 sjtag2apb_bypass_test"
  "sjtag2apb_0005 sjtag2apb_apb_write_basic_test"
  "sjtag2apb_0006 sjtag2apb_apb_write_burst_test"
  "sjtag2apb_0007 sjtag2apb_apb_read_basic_test"
  "sjtag2apb_0008 sjtag2apb_apb_read_after_write_test"
  "sjtag2apb_0009 sjtag2apb_apb_wait_state_test"
  "sjtag2apb_0010 sjtag2apb_apb_slverr_test"
  "sjtag2apb_0011 sjtag2apb_cdc_freq_ratio_test +TCK_HALF_NS=100"
  "sjtag2apb_0012 sjtag2apb_cdc_back2back_test"
  "sjtag2apb_0013 sjtag2apb_random_regression_test +TRANS_NUM=100"
)

PASS=0; FAIL=0
for entry in "${TESTS[@]}"; do
  read -r id test extra <<< "$entry"
  ./simv -l ${id}.log +UVM_TESTNAME=${test} +UVM_VERBOSITY=UVM_LOW ${extra}
  if grep -q "UVM_ERROR\s*:\s*[^0]" ${id}.log; then
    echo "FAIL: ${id} (${test})"
    FAIL=$((FAIL+1))
  else
    echo "PASS: ${id} (${test})"
    PASS=$((PASS+1))
  fi
done

echo ""
echo "=============================="
echo " 回归结果：PASS=${PASS}  FAIL=${FAIL}"
echo "=============================="
```

---

## 覆盖率收集

编译时增加 `-cm line+cond+fsm+branch+tgl` 开关，运行后合并：

```bash
# 编译（增加覆盖率开关）
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
    -cm line+cond+fsm+branch+tgl \
    -f ${REPO_ROOT}/verif/sjtag2apb/dut.flist \
    -o simv

# 运行单个用例并收集覆盖率
./simv +UVM_TESTNAME=sjtag2apb_random_regression_test \
       +TRANS_NUM=200 -cm line+cond+fsm+branch+tgl \
       -cm_dir regression.vdb

# 合并多个 session 的覆盖率数据库
urg -dir regression.vdb -report cov_report -format both
```
