"""
test_smoke.py - Smoke 测试

对应 UVM 用例：
  sjtag2apb_0001  tap_hard_reset
  sjtag2apb_0003  idcode_read

测试内容：
  1. TAP 复位后读取 IDCODE，验证与设计参数一致
  2. 多次复位后 IDCODE 一致性
"""

import cocotb
from cocotb.triggers import Timer
from .conftest import setup_tb

# 与 sjtag2apb_pkg.sv 中 IDCODE_VAL 保持一致
EXPECTED_IDCODE = 0x0A5A5001


@cocotb.test()
async def test_tap_reset_idcode(dut):
    """TAP 复位后读取 IDCODE"""
    jtag, _ = await setup_tb(dut)

    idcode = await jtag.idcode_read()
    dut._log.info(f"IDCODE = 0x{idcode:08X}")

    assert idcode == EXPECTED_IDCODE, \
        f"IDCODE mismatch: got 0x{idcode:08X}, expected 0x{EXPECTED_IDCODE:08X}"


@cocotb.test()
async def test_idcode_repeated(dut):
    """多次读取 IDCODE，验证结果一致"""
    jtag, _ = await setup_tb(dut)

    for i in range(5):
        idcode = await jtag.idcode_read()
        assert idcode == EXPECTED_IDCODE, \
            f"[iter {i}] IDCODE mismatch: got 0x{idcode:08X}"
        dut._log.info(f"[iter {i}] IDCODE = 0x{idcode:08X} OK")


@cocotb.test()
async def test_tap_reset_multiple(dut):
    """多次 TAP 复位后功能正常"""
    jtag, _ = await setup_tb(dut)

    for i in range(3):
        await jtag.tap_reset()
        idcode = await jtag.idcode_read()
        assert idcode == EXPECTED_IDCODE, \
            f"[reset {i}] IDCODE mismatch: got 0x{idcode:08X}"
    dut._log.info("Multiple TAP reset: PASSED")
