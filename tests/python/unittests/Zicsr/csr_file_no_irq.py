"""Testes do modulo.

csr_file without has_interrupts (the default): the interrupt lines
are ignored, mip and mie read zero and ignore writes, and nothing is
pending.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.csr_file import access, read

RW = 0b001
MSCRATCH, MIE, MIP = 0x340, 0x304, 0x344
ALL_ONES = 0xFFFFFFFF


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_commit.value = 0
    dut.i_addr.value = MSCRATCH
    dut.i_op.value = RW
    dut.i_wdata.value = 0
    dut.i_src_zero.value = 1
    dut.i_trap_take.value = 0
    dut.i_mret_take.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)


@cocotb.test()
async def test_lines_and_writes_are_ignored(dut):
    """Verifica the lines do not reach mip, mie or pending."""
    await _reset(dut)
    dut.i_irq_software.value = 1
    dut.i_irq_timer.value = 1
    dut.i_irq_external.value = 1
    await access(dut, MIE, RW, ALL_ONES)
    await Timer(1, unit="ns")
    check_equal(await read(dut, MIP), 0)
    check_equal(await read(dut, MIE), 0)
    check_equal(int(dut.o_irq_pending.value), 0)
