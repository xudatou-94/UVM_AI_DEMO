"""
test_apb_advanced.py - APB 高级测试

对应 UVM 用例：
  sjtag2apb_0009  apb_wait_state   (PREADY 延迟响应)
  sjtag2apb_0010  apb_slverr       (从机错误响应)
  sjtag2apb_0006  apb_write_burst  (连续写)
"""

import random
import cocotb
from cocotb.triggers import Timer
from .conftest import setup_tb


@cocotb.test()
async def test_apb_wait_state(dut):
    """APB 从机带等待周期响应（对应 sjtag2apb_0009）"""
    # wait_states=2 表示 PREADY 延迟 2 个周期
    jtag, slave = await setup_tb(dut, wait_states=2)

    addr  = 0x0000_0200
    wdata = 0x5A5A_5A5A

    await jtag.apb_write(addr, wdata)
    rdata = await jtag.apb_read(addr)

    assert rdata == wdata, \
        f"Wait state test failed: got 0x{rdata:08X}, exp 0x{wdata:08X}"
    dut._log.info(f"apb_wait_state (2 cycles): PASSED, data=0x{rdata:08X}")


@cocotb.test()
async def test_apb_slverr(dut):
    """APB 从机错误响应（对应 sjtag2apb_0010）"""
    slverr_addr = 0x0000_0400
    jtag, slave = await setup_tb(dut, slverr_addrs=[slverr_addr])

    # 向 slverr 地址写入（DUT 应能处理 PSLVERR 不崩溃）
    await jtag.apb_write(slverr_addr, 0x1234_5678)
    dut._log.info("SLVERR write completed (no crash)")

    # 向正常地址写读验证 DUT 仍然正常工作
    normal_addr  = 0x0000_0100
    normal_data  = 0xABCD_EF01
    await jtag.apb_write(normal_addr, normal_data)
    rdata = await jtag.apb_read(normal_addr)

    assert rdata == normal_data, \
        f"Post-SLVERR normal access failed: got 0x{rdata:08X}"
    dut._log.info("apb_slverr: DUT functional after SLVERR, PASSED")


@cocotb.test()
async def test_apb_write_burst(dut):
    """连续 burst 写+回读（对应 sjtag2apb_0006）"""
    jtag, slave = await setup_tb(dut)

    N = 10
    base_addr = 0x0000_1000

    for i in range(N):
        addr  = base_addr + i * 4
        wdata = 0xA000_0000 | i
        await jtag.apb_write(addr, wdata)
        rdata = await jtag.apb_read(addr)
        assert rdata == wdata, \
            f"[{i}] addr=0x{addr:08X}: got 0x{rdata:08X}, exp 0x{wdata:08X}"
        dut._log.info(f"[{i}] addr=0x{addr:08X} data=0x{wdata:08X} OK")

    dut._log.info(f"apb_write_burst ({N} beats): PASSED")
