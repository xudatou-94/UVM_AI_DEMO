"""
apb_slave.py - APB 从机模型（cocotb）

功能：
  - 监听 PSEL/PENABLE/PWRITE/PADDR/PWDATA
  - 驱动 PRDATA/PREADY/PSLVERR
  - 内部维护 memory dict 存储写入数据
  - 支持可配置 wait_states 和 slverr 注入
"""

import cocotb
from cocotb.triggers import RisingEdge


class ApbSlave:
    """简单 APB 从机模型，运行在独立 coroutine 中"""

    def __init__(self, dut, wait_states=0, slverr_addrs=None):
        self.dut         = dut
        self.wait_states = wait_states          # 固定等待周期数
        self.slverr_addrs = slverr_addrs or []  # 返回 SLVERR 的地址列表
        self.mem         = {}                   # {addr: data}

        # 初始化输出信号
        dut.prdata.value  = 0
        dut.pready.value  = 0
        dut.pslverr.value = 0

    async def run(self):
        """主循环：在独立 cocotb.start_soon() 中运行"""
        while True:
            await RisingEdge(self.dut.pclk)
            if not self.dut.presetn.value:
                self.dut.prdata.value  = 0
                self.dut.pready.value  = 0
                self.dut.pslverr.value = 0
                continue

            # SETUP 阶段：PSEL=1, PENABLE=0
            if self.dut.psel.value and not self.dut.penable.value:
                # 等待 wait_states 个周期再拉高 PREADY
                for _ in range(self.wait_states):
                    await RisingEdge(self.dut.pclk)

                addr   = int(self.dut.paddr.value)
                pwrite = int(self.dut.pwrite.value)

                # 判断是否注入 SLVERR
                is_err = addr in self.slverr_addrs

                if pwrite:
                    # 写操作
                    wdata = int(self.dut.pwdata.value)
                    if not is_err:
                        self.mem[addr] = wdata
                    self.dut.prdata.value  = 0
                else:
                    # 读操作
                    rdata = self.mem.get(addr, 0xDEAD_BEEF)
                    self.dut.prdata.value  = rdata

                self.dut.pready.value  = 1
                self.dut.pslverr.value = 1 if is_err else 0

                # ACCESS 阶段完成后清零
                await RisingEdge(self.dut.pclk)
                self.dut.pready.value  = 0
                self.dut.pslverr.value = 0
                self.dut.prdata.value  = 0

    def read_mem(self, addr):
        return self.mem.get(addr, 0)
