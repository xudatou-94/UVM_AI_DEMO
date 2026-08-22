"""
sjtag_driver.py - SJTAG/JTAG bit-bang driver for cocotb

对应 UVM sjtag_driver.sv 中的 TAP 操作逻辑：
  - tap_reset()         : TMS 连续 5 个上升沿复位 TAP
  - shift_ir(ir_val)    : 移入 IR 指令（4bit）
  - shift_dr(dr_in, n)  : 移入/移出 DR（n bit）
  - apb_write(addr, data)
  - apb_read(addr) -> rdata
  - idcode_read()  -> idcode
"""

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer


class SjtagDriver:
    """JTAG bit-bang driver，操作 TCK/TMS/TDI/TRST_N 信号"""

    # IR 指令编码（与 sjtag2apb_pkg.sv 一致）
    INSTR_BYPASS     = 0xF
    INSTR_IDCODE     = 0x1
    INSTR_APB_ACCESS = 0x2

    def __init__(self, dut, tck_period_ns=20):
        self.dut         = dut
        self.tck_period  = tck_period_ns  # ns

        # 初始化信号
        dut.tck.value    = 0
        dut.tms.value    = 1
        dut.tdi.value    = 0
        dut.trst_n.value = 0

    async def _tck_cycle(self, tms_val=0, tdi_val=0):
        """产生一个 TCK 上升沿，采样 TDO"""
        self.dut.tms.value = tms_val
        self.dut.tdi.value = tdi_val
        await Timer(self.tck_period // 2, units="ns")
        self.dut.tck.value = 1
        await Timer(self.tck_period // 2, units="ns")
        tdo = int(self.dut.tdo.value)
        self.dut.tck.value = 0
        return tdo

    async def release_reset(self):
        """释放 TRST_N，进入 Test-Logic-Reset"""
        self.dut.trst_n.value = 0
        await Timer(100, units="ns")
        self.dut.trst_n.value = 1
        await Timer(self.tck_period, units="ns")

    async def tap_reset(self):
        """TAP 复位：TMS=1 连续 5 个时钟后回 RTI"""
        for _ in range(5):
            await self._tck_cycle(tms_val=1)
        # Test-Logic-Reset → Run-Test/Idle
        await self._tck_cycle(tms_val=0)

    async def _goto_shift_ir(self):
        """Run-Test/Idle → Shift-IR"""
        await self._tck_cycle(tms_val=1)  # Select-DR-Scan
        await self._tck_cycle(tms_val=1)  # Select-IR-Scan
        await self._tck_cycle(tms_val=0)  # Capture-IR
        await self._tck_cycle(tms_val=0)  # Shift-IR

    async def _goto_shift_dr(self):
        """Run-Test/Idle → Shift-DR"""
        await self._tck_cycle(tms_val=1)  # Select-DR-Scan
        await self._tck_cycle(tms_val=0)  # Capture-DR
        await self._tck_cycle(tms_val=0)  # Shift-DR

    async def _exit_to_rti(self):
        """Exit1 → Update → Run-Test/Idle"""
        await self._tck_cycle(tms_val=1)  # Update-DR/IR
        await self._tck_cycle(tms_val=0)  # Run-Test/Idle

    async def shift_ir(self, ir_val, ir_len=4):
        """移入 IR 寄存器（LSB first）"""
        await self._goto_shift_ir()
        for i in range(ir_len):
            bit = (ir_val >> i) & 1
            tms = 1 if (i == ir_len - 1) else 0  # 最后一位时 TMS=1 退出
            await self._tck_cycle(tms_val=tms, tdi_val=bit)
        await self._exit_to_rti()

    async def shift_dr(self, dr_in, dr_len):
        """移入/移出 DR 寄存器（LSB first），返回移出的值"""
        await self._goto_shift_dr()
        dr_out = 0
        for i in range(dr_len):
            bit = (dr_in >> i) & 1
            tms = 1 if (i == dr_len - 1) else 0
            tdo = await self._tck_cycle(tms_val=tms, tdi_val=bit)
            dr_out |= (tdo << i)
        await self._exit_to_rti()
        return dr_out

    async def apb_write(self, addr, data):
        """
        APB 写操作：
          DR[64]=1(写), DR[63:32]=addr, DR[31:0]=data
        """
        dr_in = (1 << 64) | ((addr & 0xFFFFFFFF) << 32) | (data & 0xFFFFFFFF)
        await self.shift_ir(self.INSTR_APB_ACCESS)
        await self.shift_dr(dr_in, 65)
        # 等待 APB 事务完成（保守等待 20 个 TCK）
        for _ in range(20):
            await self._tck_cycle(tms_val=0)

    async def apb_read(self, addr):
        """
        APB 读操作（两次 DR 扫描）：
          第一次：DR[64]=0, DR[63:32]=addr → 触发读请求
          等待 APB 事务完成
          第二次：CAPTURE_DR 时 DUT 将读数据装入 DR → 移出读数据
        返回：32-bit rdata
        """
        dr_in = (0 << 64) | ((addr & 0xFFFFFFFF) << 32)

        # 第一次扫描：发送读请求
        await self.shift_ir(self.INSTR_APB_ACCESS)
        await self.shift_dr(dr_in, 65)

        # 等待 APB 完成
        for _ in range(20):
            await self._tck_cycle(tms_val=0)

        # 第二次扫描：取回读数据
        await self.shift_ir(self.INSTR_APB_ACCESS)
        dr_out = await self.shift_dr(dr_in, 65)

        return dr_out & 0xFFFFFFFF

    async def idcode_read(self):
        """读取 IDCODE（32bit）"""
        await self.shift_ir(self.INSTR_IDCODE)
        idcode = await self.shift_dr(0, 32)
        return idcode & 0xFFFFFFFF
