"""Testes do modulo.

csr_file with has_interrupts: mip mirrors the three interrupt lines
and is read-only, mie keeps the bits 3, 7 and 11, and the pending
output is the lines under the mask. The generic comes from the entry
of tests.json.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.csr_file import access, read

RW, RS, RC = 0b001, 0b010, 0b011
MSTATUS, MIE, MTVEC, MSCRATCH, MIP = 0x300, 0x304, 0x305, 0x340, 0x344
SOFTWARE, TIMER, EXTERNAL = 1 << 3, 1 << 7, 1 << 11
MASK = SOFTWARE | TIMER | EXTERNAL
ALL_ONES = 0xFFFFFFFF
MIE_BIT = 0x8
CAUSE_SOFTWARE, CAUSE_TIMER, CAUSE_EXTERNAL = (
    0x80000003,
    0x80000007,
    0x8000000B,
)


def _lines(dut, software=0, timer=0, external=0):
    """Drive the three interrupt lines."""
    dut.i_irq_software.value = software
    dut.i_irq_timer.value = timer
    dut.i_irq_external.value = external


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_commit.value = 0
    dut.i_addr.value = MSCRATCH
    dut.i_op.value = RS
    dut.i_wdata.value = 0
    dut.i_src_zero.value = 1
    dut.i_trap_take.value = 0
    dut.i_mret_take.value = 0
    _lines(dut)
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)


async def _pending(dut):
    """Return the pending output after the lines settle."""
    await Timer(1, unit="ns")
    return int(dut.o_irq_pending.value)


@cocotb.test()
async def test_reset_reads_zero_and_nothing_is_pending(dut):
    """Verifica mip and mie read zero at reset with the lines low."""
    await _reset(dut)
    check_equal(await read(dut, MIP), 0)
    check_equal(await read(dut, MIE), 0)
    check_equal(await _pending(dut), 0)


@cocotb.test()
async def test_mip_mirrors_each_line_at_its_bit(dut):
    """Verifica mip shows software, timer and external at 3, 7, 11."""
    await _reset(dut)
    cases = ((1, 0, 0, SOFTWARE), (0, 1, 0, TIMER), (0, 0, 1, EXTERNAL))
    for software, timer, external, want in cases:
        _lines(dut, software, timer, external)
        await Timer(1, unit="ns")
        check_equal(await read(dut, MIP), want)
    _lines(dut, 1, 1, 1)
    await Timer(1, unit="ns")
    check_equal(await read(dut, MIP), MASK)
    _lines(dut)
    await Timer(1, unit="ns")
    check_equal(await read(dut, MIP), 0)


@cocotb.test()
async def test_a_write_to_mip_is_legal_and_ignored(dut):
    """Verifica a write to mip is legal and does not change it."""
    await _reset(dut)
    check_equal((await access(dut, MIP, RW, ALL_ONES))[1], 0)
    check_equal(await read(dut, MIP), 0)
    _lines(dut, 0, 1, 0)
    await Timer(1, unit="ns")
    await access(dut, MIP, RC, ALL_ONES)
    check_equal(await read(dut, MIP), TIMER)


@cocotb.test()
async def test_mie_keeps_only_bits_3_7_and_11(dut):
    """Verifica mie guarda só os bits 3, 7 e 11."""
    await _reset(dut)
    check_equal((await access(dut, MIE, RW, ALL_ONES))[1], 0)
    check_equal(await read(dut, MIE), MASK)
    await access(dut, MIE, RC, TIMER)
    check_equal(await read(dut, MIE), SOFTWARE | EXTERNAL)
    await access(dut, MIE, RS, TIMER)
    check_equal(await read(dut, MIE), MASK)
    await access(dut, MIE, RW, 0x777)
    check_equal(await read(dut, MIE), 0)


@cocotb.test()
async def test_mie_ignores_a_write_without_commit(dut):
    """Verifica mie does not change when the commit is low."""
    await _reset(dut)
    dut.i_addr.value = MIE
    dut.i_op.value = RW
    dut.i_wdata.value = MASK
    dut.i_src_zero.value = 0
    dut.i_commit.value = 0
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_equal(await read(dut, MIE), 0)


@cocotb.test()
async def test_pending_is_the_lines_under_the_mask(dut):
    """Verifica o_irq_pending is one when a line meets its mask bit."""
    await _reset(dut)
    _lines(dut, 0, 1, 0)
    check_equal(await _pending(dut), 0)
    await access(dut, MIE, RW, SOFTWARE | EXTERNAL)
    check_equal(await _pending(dut), 0)
    await access(dut, MIE, RS, TIMER)
    check_equal(await _pending(dut), 1)
    _lines(dut, 0, 0, 0)
    check_equal(await _pending(dut), 0)
    _lines(dut, 1, 0, 0)
    check_equal(await _pending(dut), 1)


@cocotb.test()
async def test_pending_ignores_mstatus_mie(dut):
    """Verifica o_irq_pending does not look at mstatus.MIE."""
    await _reset(dut)
    await access(dut, MIE, RW, EXTERNAL)
    _lines(dut, 0, 0, 1)
    for value in (0, MIE_BIT):
        await access(dut, MSTATUS, RW, value)
        check_equal(await _pending(dut), 1)


@cocotb.test()
async def test_a_trap_cycle_does_not_write_mie(dut):
    """Verifica a CSR write in a trap cycle does not land in mie."""
    await _reset(dut)
    dut.i_trap_take.value = 1
    await access(dut, MIE, RW, MASK)
    dut.i_trap_take.value = 0
    check_equal(await read(dut, MIE), 0)


@cocotb.test()
async def test_take_needs_mstatus_mie_and_a_pending_enabled_line(dut):
    """Verifica o_irq_take: MIE, linha e máscara, os três em 1."""
    await _reset(dut)
    _lines(dut, 0, 1, 0)
    await access(dut, MIE, RW, TIMER)
    for value, want in ((0, 0), (MIE_BIT, 1)):
        await access(dut, MSTATUS, RW, value)
        await Timer(1, unit="ns")
        check_equal(int(dut.o_irq_take.value), want, f"MIE {value:#x}")
    await access(dut, MIE, RW, SOFTWARE | EXTERNAL)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_irq_take.value), 0)
    await access(dut, MIE, RW, TIMER)
    _lines(dut, 0, 0, 0)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_irq_take.value), 0)


@cocotb.test()
async def test_cause_priority_is_external_software_timer(dut):
    """Verifica o_irq_cause: externa, software e timer, nessa ordem."""
    await _reset(dut)
    await access(dut, MIE, RW, MASK)
    cases = (
        ((1, 1, 1), CAUSE_EXTERNAL),
        ((1, 1, 0), CAUSE_SOFTWARE),
        ((0, 1, 1), CAUSE_EXTERNAL),
        ((1, 0, 1), CAUSE_EXTERNAL),
        ((0, 1, 0), CAUSE_TIMER),
        ((1, 0, 0), CAUSE_SOFTWARE),
        ((0, 0, 1), CAUSE_EXTERNAL),
    )
    for lines, want in cases:
        _lines(dut, *lines)
        await Timer(1, unit="ns")
        check_equal(int(dut.o_irq_cause.value), want, f"linhas {lines}")


@cocotb.test()
async def test_cause_skips_a_masked_line(dut):
    """Verifica que uma linha mascarada não toma a prioridade."""
    await _reset(dut)
    await access(dut, MIE, RW, TIMER | SOFTWARE)
    _lines(dut, 1, 1, 1)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_irq_cause.value), CAUSE_SOFTWARE)
    await access(dut, MIE, RW, TIMER)
    check_equal(int(dut.o_irq_cause.value), CAUSE_TIMER)


@cocotb.test()
async def test_mtvec_mode_bit_is_kept_and_base_is_aligned(dut):
    """Verifica mtvec: modo vetorado no bit 0 e BASE de 64 bytes."""
    await _reset(dut)
    await access(dut, MTVEC, RW, 0x00001001)
    check_equal(await read(dut, MTVEC), 0x00001001)
    check_equal(int(dut.o_mtvec_vectored.value), 1)
    check_equal(int(dut.o_mtvec.value), 0x00001000)
    await access(dut, MTVEC, RW, 0x000010FD)
    check_equal(await read(dut, MTVEC), 0x000010C1)
    check_equal(int(dut.o_mtvec.value), 0x000010C0)
    await access(dut, MTVEC, RW, 0x000010FC)
    check_equal(await read(dut, MTVEC), 0x000010FC)
    check_equal(int(dut.o_mtvec_vectored.value), 0)
    await access(dut, MTVEC, RW, 0x00001003)
    check_equal(await read(dut, MTVEC), 0x00001001)
