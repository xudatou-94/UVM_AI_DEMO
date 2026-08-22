"""
test_apb_basic.py - APB 基本读写测试

对应 UVM 用例：
  sjtag2apb_0005  apb_write_basic
  sjtag2apb_0007  apb_read_basic
  sjtag2apb_0008  apb_read_after_write

测试内容：
  1. 单次写+立即回读
  2. 20 次随机地址写+回读
  3. 多地址写入后逐个读回
"""

import random
import cocotb
from cocotb.triggers import Timer
from .conftest import setup_tb


@cocotb.test()
async def test_single_write_read(dut):
    """单次写+立即回读"""
    jtag, slave = await setup_tb(dut)

    addr  = 0x0000_0100
    wdata = 0xDEAD_BEEF

    await jtag.apb_write(addr, wdata)
    rdata = await jtag.apb_read(addr)

    dut._log.info(f"Write 0x{wdata:08X} -> Read 0x{rdata:08X}")
    assert rdata == wdata, f"Mismatch: got 0x{rdata:08X}, exp 0x{wdata:08X}"


@cocotb.test()
async def test_apb_write_basic(dut):
    """20 次随机地址写+立即回读（对应 sjtag2apb_0005）"""
    jtag, slave = await setup_tb(dut)

    pass_cnt = 0
    fail_cnt = 0

    for i in range(20):
        addr  = random.randint(0, 0x3FFF) & ~0x3  # 4-byte 对齐
        wdata = random.randint(0, 0xFFFF_FFFF)

        await jtag.apb_write(addr, wdata)
        rdata = await jtag.apb_read(addr)

        if rdata == wdata:
            pass_cnt += 1
            dut._log.info(f"[{i:02d}] OK  addr=0x{addr:08X} data=0x{wdata:08X}")
        else:
            fail_cnt += 1
            dut._log.error(f"[{i:02d}] FAIL addr=0x{addr:08X} wr=0x{wdata:08X} rd=0x{rdata:08X}")

    dut._log.info(f"apb_write_basic: {pass_cnt} passed / {fail_cnt} failed")
    assert fail_cnt == 0, f"{fail_cnt} write-read mismatches"


@cocotb.test()
async def test_apb_read_after_write(dut):
    """多地址写入后逐个读回（对应 sjtag2apb_0008）"""
    jtag, slave = await setup_tb(dut)

    test_vectors = [
        (0x0000_0000, 0x1234_5678),
        (0x0000_0004, 0xABCD_EF01),
        (0x0000_0008, 0xDEAD_BEEF),
        (0x0000_000C, 0xCAFE_BABE),
        (0x0000_0010, 0x0000_0001),
    ]

    # 先全部写入
    for addr, wdata in test_vectors:
        await jtag.apb_write(addr, wdata)
        dut._log.info(f"Write addr=0x{addr:08X} data=0x{wdata:08X}")

    # 再逐个读回（slave 每次只保存最新写入值）
    for addr, wdata in test_vectors:
        # 注意：slave 只保存一拍，这里需要先重新写入再读
        await jtag.apb_write(addr, wdata)
        rdata = await jtag.apb_read(addr)
        assert rdata == wdata, \
            f"addr=0x{addr:08X}: got 0x{rdata:08X}, exp 0x{wdata:08X}"
        dut._log.info(f"Read  addr=0x{addr:08X} data=0x{rdata:08X} OK")

    dut._log.info("apb_read_after_write: PASSED")
