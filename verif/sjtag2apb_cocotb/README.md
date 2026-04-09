# sjtag2apb cocotb 验证环境

基于 [cocotb](https://www.cocotb.org/) 的 sjtag2apb 协议转换桥验证环境，与 `verif/sjtag2apb/`（UVM 版本）验证同一 DUT。

---

## 环境依赖

```bash
pip install -r requirements.txt
```

仿真器（二选一）：
- **Icarus Verilog**（免费）：`sudo apt install iverilog`
- **Synopsys VCS**：需商业 License，环境变量参考 `scripts/setup.sh`

---

## 快速开始

```bash
cd verif/sjtag2apb_cocotb/

# 使用 Icarus（默认）运行全部测试
make

# 使用 VCS 运行
make SIM=vcs
```

---

## 运行指定测试

```bash
# 只运行 smoke 测试
make smoke

# 只运行 APB 基本读写测试
make apb_basic

# 只运行 APB 高级测试（wait_state / slverr / burst）
make apb_advanced

# 只运行 BYPASS 测试
make bypass

# 运行单个测试函数
make MODULE=tests.test_smoke TESTCASE=test_tap_reset_idcode
```

---

## 测试用例列表

| 文件 | 测试函数 | 对应 UVM 用例 | 说明 |
|------|----------|---------------|------|
| `test_smoke.py` | `test_tap_reset_idcode` | sjtag2apb_0001/0003 | TAP 复位 + IDCODE 读取 |
| `test_smoke.py` | `test_idcode_repeated` | sjtag2apb_0003 | 多次 IDCODE 一致性 |
| `test_smoke.py` | `test_tap_reset_multiple` | sjtag2apb_0001 | 多次 TAP 复位后功能验证 |
| `test_apb_basic.py` | `test_single_write_read` | sjtag2apb_0005 | 单次写+回读 |
| `test_apb_basic.py` | `test_apb_write_basic` | sjtag2apb_0005 | 20次随机写+立即回读 |
| `test_apb_basic.py` | `test_apb_read_after_write` | sjtag2apb_0008 | 多地址写入后逐个读回 |
| `test_apb_advanced.py` | `test_apb_wait_state` | sjtag2apb_0009 | PREADY 延迟 2 周期 |
| `test_apb_advanced.py` | `test_apb_slverr` | sjtag2apb_0010 | PSLVERR 注入后恢复 |
| `test_apb_advanced.py` | `test_apb_write_burst` | sjtag2apb_0006 | 连续 10 次写+回读 |
| `test_bypass.py` | `test_bypass_shift` | sjtag2apb_0004 | BYPASS 1-bit 延迟验证 |

---

## 目录结构

```
verif/sjtag2apb_cocotb/
├── Makefile              # cocotb Makefile（支持 icarus/vcs）
├── requirements.txt      # Python 依赖
├── README.md
├── tb/
│   ├── __init__.py
│   ├── sjtag_driver.py   # JTAG bit-bang 驱动（对应 UVM sjtag_driver.sv）
│   └── apb_slave.py      # APB 从机模型（内存 dict + wait_states + slverr）
└── tests/
    ├── __init__.py
    ├── conftest.py        # 公共 setup（时钟、复位、驱动初始化）
    ├── test_smoke.py      # TAP 复位 + IDCODE
    ├── test_apb_basic.py  # APB 基本读写
    ├── test_apb_advanced.py # wait_state / slverr / burst
    └── test_bypass.py     # BYPASS 指令
```

---

## 与 UVM 版本对比

| 特性 | cocotb | UVM |
|------|--------|-----|
| 语言 | Python | SystemVerilog |
| JTAG 驱动 | `sjtag_driver.py` | `sjtag_driver.sv` |
| APB 从机 | `apb_slave.py` (dict) | `apb_slave_driver.sv` (TLM FIFO) |
| Scoreboard | assert 语句 | `sjtag2apb_scoreboard.sv` |
| 覆盖率 | 依赖仿真器 | covergroup |
| 免费仿真器 | Icarus / Verilator | 不支持 |
