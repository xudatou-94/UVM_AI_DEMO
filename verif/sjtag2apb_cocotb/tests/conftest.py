"""
conftest.py - pytest/cocotb 公共 fixture

提供所有测试共享的 setup：
  - PCLK 时钟驱动
  - APB Slave 模型启动
  - JTAG Driver 初始化 + 复位
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

from tb.sjtag_driver import SjtagDriver
from tb.apb_slave import ApbSlave


async def setup_tb(dut, wait_states=0, slverr_addrs=None):
    """
    公共 TB 初始化：
      1. 启动 PCLK（50 MHz，20 ns）
      2. 启动 APB Slave 模型
      3. 初始化 JTAG Driver，执行复位
    返回 (jtag, apb_slave)
    """
    # 启动 PCLK
    cocotb.start_soon(Clock(dut.pclk, 20, units="ns").start())

    # APB slave
    slave = ApbSlave(dut, wait_states=wait_states, slverr_addrs=slverr_addrs or [])
    cocotb.start_soon(slave.run())

    # 复位序列
    dut.presetn.value = 0
    await Timer(200, units="ns")
    dut.presetn.value = 1

    # JTAG driver
    jtag = SjtagDriver(dut, tck_period_ns=40)  # TCK 25 MHz
    await jtag.release_reset()
    await jtag.tap_reset()

    return jtag, slave
