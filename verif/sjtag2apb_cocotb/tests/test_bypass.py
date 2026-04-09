"""
test_bypass.py - BYPASS 指令测试

对应 UVM 用例：
  sjtag2apb_0004  bypass

测试内容：
  移入 BYPASS 指令后，TDI 经 1 bit 延迟从 TDO 输出
"""

import cocotb
from .conftest import setup_tb
from tb.sjtag_driver import SjtagDriver


@cocotb.test()
async def test_bypass_shift(dut):
    """BYPASS 模式：TDI 延迟 1 bit 后从 TDO 输出"""
    jtag, _ = await setup_tb(dut)

    # 切换到 BYPASS 指令
    await jtag.shift_ir(SjtagDriver.INSTR_BYPASS)

    # 移入已知 8-bit 图样，读回应该是同样的图样（延迟 1 bit）
    # 实际移出 9 bit，忽略第一个 bit（bypass 寄存器初始值不定）
    pattern_in = 0b1010_1010   # 8 bit
    dr_out = await jtag.shift_dr(pattern_in, 9)  # 多移 1 bit 补偿延迟

    # 取 dr_out[8:1]（去掉最低的 1 bit 延迟）
    captured = (dr_out >> 1) & 0xFF
    dut._log.info(f"BYPASS: in=0b{pattern_in:08b} out=0b{captured:08b}")

    assert captured == pattern_in, \
        f"BYPASS mismatch: in=0b{pattern_in:08b} out=0b{captured:08b}"
    dut._log.info("test_bypass_shift: PASSED")
