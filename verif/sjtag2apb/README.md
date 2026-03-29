# sjtag2apb 激励运行指南

所有命令均在 `scripts/` 目录下执行，通过 `Makefile` 统一管理。

```bash
cd scripts/
```

## 环境初始化

```bash
source setup.sh
```

---

## 编译

```bash
make compile PROJ=sjtag2apb
```

---

## 单条激励运行

```bash
# 仅运行（需已编译）
make run PROJ=sjtag2apb TC=<test_class>

# 编译 + 运行一步完成
make all PROJ=sjtag2apb TC=<test_class>
```

各用例对应的测试类名：

| case_id | case_name | TC（测试类名）|
|---|---|---|
| sjtag2apb_0001 | tap_hard_reset | `sjtag2apb_tap_hard_reset_test` |
| sjtag2apb_0002 | tap_soft_reset | `sjtag2apb_tap_soft_reset_test` |
| sjtag2apb_0003 | idcode_read | `sjtag2apb_idcode_read_test` |
| sjtag2apb_0004 | bypass | `sjtag2apb_bypass_test` |
| sjtag2apb_0005 | apb_write_basic | `sjtag2apb_apb_write_basic_test` |
| sjtag2apb_0006 | apb_write_burst | `sjtag2apb_apb_write_burst_test` |
| sjtag2apb_0007 | apb_read_basic | `sjtag2apb_apb_read_basic_test` |
| sjtag2apb_0008 | apb_read_after_write | `sjtag2apb_apb_read_after_write_test` |
| sjtag2apb_0009 | apb_wait_state | `sjtag2apb_apb_wait_state_test` |
| sjtag2apb_0010 | apb_slverr | `sjtag2apb_apb_slverr_test` |
| sjtag2apb_0011 | cdc_freq_ratio | `sjtag2apb_cdc_freq_ratio_test` |
| sjtag2apb_0012 | cdc_back2back | `sjtag2apb_cdc_back2back_test` |
| sjtag2apb_0013 | random_regression | `sjtag2apb_random_regression_test` |

示例：

```bash
make all PROJ=sjtag2apb TC=sjtag2apb_apb_write_basic_test
make all PROJ=sjtag2apb TC=sjtag2apb_apb_write_basic_test SEED=12345 VERBOSITY=UVM_HIGH
```

---

## 批量回归

运行全部用例：

```bash
make regress PROJ=sjtag2apb
```

按标签过滤（标签定义见 `case_list.json`）：

```bash
make regress PROJ=sjtag2apb TAG=smoke
make regress PROJ=sjtag2apb TAG=apb
make regress PROJ=sjtag2apb TAG=cdc
```

按 case_id 或 case_name 过滤：

```bash
make regress PROJ=sjtag2apb CASE_ID=sjtag2apb_0005
make regress PROJ=sjtag2apb CASE_REGEX='sjtag2apb_apb_write.*'
```

并行运行（本地 4 进程）：

```bash
make regress PROJ=sjtag2apb JOBS=4
```

重跑上次失败的用例：

```bash
make rerun PROJ=sjtag2apb
```

---

## 覆盖率

```bash
# 开启覆盖率运行全部用例
make regress PROJ=sjtag2apb CODE_COV=1 FUNC_COV=1 JOBS=4

# 合并覆盖率数据并生成报告
make merge_cov PROJ=sjtag2apb
```

---

## 回归报告

```bash
make report PROJ=sjtag2apb
```

---

## 波形调试

```bash
make debug PROJ=sjtag2apb TC=sjtag2apb_apb_slverr_test
```

---

## 常用变量速查

| 变量 | 默认值 | 说明 |
|---|---|---|
| `TC` | `base_test` | 测试类名 |
| `SEED` | `random` | 随机种子 |
| `VERBOSITY` | `UVM_MEDIUM` | UVM 打印级别 |
| `WAVE` | `1` | 是否转储波形 |
| `CODE_COV` | `0` | 代码覆盖率（1=开启）|
| `FUNC_COV` | `0` | 功能覆盖率（1=开启）|
| `JOBS` | `1` | 本地并行进程数 |
| `SUBMIT` | `local` | 提交方式（local/lsf/sge）|

完整帮助：

```bash
make help
```

> 以上命令均在 `scripts/` 目录下执行。
