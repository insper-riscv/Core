"""Testes do modulo.

csr_file: Zicsr read/modify/write semantics and the machine-mode CSR
bank.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

READ_ONLY_SPACE = 0b11

RW, RS, RC = 0b001, 0b010, 0b011
MSTATUS, MISA, MIE, MTVEC, MSTATUSH = 0x300, 0x301, 0x304, 0x305, 0x310
MSCRATCH, MEPC, MCAUSE, MTVAL, MIP = 0x340, 0x341, 0x342, 0x343, 0x344
MVENDORID, MARCHID, MIMPID, MHARTID, MCONFIGPTR = (
    0xF11,
    0xF12,
    0xF13,
    0xF14,
    0xF15,
)


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_commit.value = 0
    dut.i_addr.value = MSCRATCH
    dut.i_op.value = RS
    dut.i_wdata.value = 0
    dut.i_src_zero.value = 1
    dut.i_trap_take.value = 0
    dut.i_trap_cause.value = 0
    dut.i_trap_pc.value = 0
    dut.i_trap_tval.value = 0
    dut.i_mret_take.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)


def _drive(dut, addr, op, wdata, src_zero):
    """Present one CSR instruction on the inputs."""
    dut.i_addr.value = addr
    dut.i_op.value = op
    dut.i_wdata.value = wdata
    dut.i_src_zero.value = int(wdata == 0) if src_zero is None else src_zero


async def _step(dut, commit):
    """Clock the presented instruction and return (old value, illegal).

    The pair is what the core shows before the write lands.
    """
    dut.i_commit.value = commit
    await Timer(1, unit="ns")
    seen = int(dut.o_rdata.value), int(dut.o_illegal.value)
    await RisingEdge(dut.i_clk)
    dut.i_commit.value = 0
    await Timer(1, unit="ns")
    return seen


async def access(dut, addr, op, wdata=0, src_zero=None):
    """Run one CSR instruction, as committed."""
    _drive(dut, addr, op, wdata, src_zero)
    return await _step(dut, 1)


async def access_stalled(dut, addr, op, wdata=0):
    """Run a CSR instruction whose commit is held low."""
    _drive(dut, addr, op, wdata, None)
    return await _step(dut, 0)


async def read(dut, addr):
    """Executa read."""
    return (await access(dut, addr, RS, 0))[0]


@cocotb.test()
async def test_reset_values(dut):
    """Verifica reset values."""
    await _reset(dut)
    want = {
        MSTATUS: 0x1800,
        MISA: 0x40001100,
        MIE: 0,
        MTVEC: 0,
        MSTATUSH: 0,
        MSCRATCH: 0,
        MEPC: 0,
        MCAUSE: 0,
        MTVAL: 0,
        MIP: 0,
        MVENDORID: 0,
        MARCHID: 0,
        MIMPID: 0,
        MHARTID: 0,
        MCONFIGPTR: 0,
    }
    for addr, value in want.items():
        check_equal(await read(dut, addr), value, f"{addr:#x}")


@cocotb.test()
async def test_csrrw_swaps(dut):
    """Verifica csrrw swaps."""
    await _reset(dut)
    check_equal(await access(dut, MSCRATCH, RW, 0xDEADBEEF), (0, 0))
    check_equal(await access(dut, MSCRATCH, RW, 0x12345678), (0xDEADBEEF, 0))
    check_equal(await read(dut, MSCRATCH), 0x12345678)


@cocotb.test()
async def test_csrrs_csrrc_bit_ops(dut):
    """Verifica csrrs csrrc bit ops."""
    await _reset(dut)
    await access(dut, MSCRATCH, RW, 0x0000FF00)
    check_equal((await access(dut, MSCRATCH, RS, 0x000000F0))[0], 0x0000FF00)
    check_equal(await read(dut, MSCRATCH), 0x0000FFF0)
    check_equal((await access(dut, MSCRATCH, RC, 0x00000FF0))[0], 0x0000FFF0)
    check_equal(await read(dut, MSCRATCH), 0x0000F000)


@cocotb.test()
async def test_set_clear_with_zero_source_does_not_write(dut):
    """Verifica set clear with zero source does not write.

    CSRRS/CSRRC with rs1 = x0 read only; a zero value from a register
    still writes nothing.
    """
    await _reset(dut)
    await access(dut, MSCRATCH, RW, 0xA5A5A5A5)
    await access(dut, MSCRATCH, RS, 0, src_zero=1)
    await access(dut, MSCRATCH, RC, 0, src_zero=1)
    check_equal(await read(dut, MSCRATCH), 0xA5A5A5A5)
    # CSRRW with a zero source writes zero (RW always writes).
    await access(dut, MSCRATCH, RW, 0, src_zero=1)
    check_equal(await read(dut, MSCRATCH), 0)


@cocotb.test()
async def test_no_commit_no_write(dut):
    """A stalled instruction (commit = 0) leaves the CSR alone."""
    await _reset(dut)
    await access_stalled(dut, MSCRATCH, RW, 0x1111)
    check_equal(await read(dut, MSCRATCH), 0)


@cocotb.test()
async def test_field_masks(dut):
    """Verifica field masks."""
    await _reset(dut)
    await access(dut, MSTATUS, RW, 0xFFFFFFFF)
    check_equal(await read(dut, MSTATUS), 0x1888)
    await access(dut, MSTATUS, RW, 0)
    check_equal(await read(dut, MSTATUS), 0x1800)
    await access(dut, MTVEC, RW, 0x80000003)
    check_equal(await read(dut, MTVEC), 0x80000000)
    await access(dut, MEPC, RW, 0x80000003)
    check_equal(await read(dut, MEPC), 0x80000000)
    await access(dut, MCAUSE, RW, 0xFFFFFFFF)
    await access(dut, MTVAL, RW, 0xFFFFFFFF)
    check_equal(await read(dut, MCAUSE), 0xFFFFFFFF)
    check_equal(await read(dut, MTVAL), 0xFFFFFFFF)
    for addr in (MIE, MSTATUSH):
        await access(dut, addr, RW, 0xFFFFFFFF)
        check_equal(await read(dut, addr), 0, f"{addr:#x}")


@cocotb.test()
async def test_read_only_csrs(dut):
    """Verifica read only csrs.

    An effective write to a read-only CSR is illegal and changes
    nothing; a read is fine.
    """
    await _reset(dut)
    for addr in (MISA, MIP, MVENDORID, MARCHID, MIMPID, MHARTID, MCONFIGPTR):
        _, illegal = await access(dut, addr, RW, 0xFFFFFFFF)
        want_illegal = int(addr >> 10 == READ_ONLY_SPACE)
        check_equal(illegal, want_illegal, f"{addr:#x} write")
        _, illegal = await access(dut, addr, RS, 0, src_zero=1)
        check_equal(illegal, 0, f"{addr:#x} read")
    check_equal(await read(dut, MISA), 0x40001100)
    check_equal(await read(dut, MIP), 0)


@cocotb.test()
async def test_unknown_csr_is_illegal(dut):
    """Verifica unknown csr is illegal."""
    await _reset(dut)
    for addr in (
        0x000,
        0x100,
        0x302,
        0x303,
        0x306,
        0x320,
        0x7A0,
        0xB00,
        0xC00,
        0xF10,
        0xFFF,
    ):
        check_equal(
            (await access(dut, addr, RS, 0, src_zero=1))[1], 1, f"{addr:#x}"
        )


async def take_trap(dut, cause, pc, tval):
    """Executa take trap."""
    dut.i_trap_cause.value = cause
    dut.i_trap_pc.value = pc
    dut.i_trap_tval.value = tval
    dut.i_trap_take.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_trap_take.value = 0
    await Timer(1, unit="ns")


async def take_mret(dut):
    """Executa take mret."""
    dut.i_mret_take.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_mret_take.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_trap_records_the_exception_and_closes_the_interrupt_enable(dut):
    """Verifica o registro da exceção e o fechamento do enable.

    Verifica trap records the exception and closes the interrupt enable.
    """
    await _reset(dut)
    await access(dut, MTVEC, RW, 0x00000200)
    await access(dut, MSTATUS, RS, 0x8)  # MIE = 1
    check_equal(await read(dut, MSTATUS), 0x1808)
    await take_trap(dut, cause=11, pc=0x00001234, tval=0x77)
    check_equal(await read(dut, MEPC), 0x1234)
    check_equal(await read(dut, MCAUSE), 11)
    check_equal(await read(dut, MTVAL), 0x77)
    check_equal(await read(dut, MSTATUS), 0x1880)
    check_equal(int(dut.o_mtvec.value), 0x200)
    check_equal(int(dut.o_mepc.value), 0x1234)


@cocotb.test()
async def test_mret_restores_the_interrupt_enable(dut):
    """Verifica mret restores the interrupt enable."""
    await _reset(dut)
    await access(dut, MSTATUS, RS, 0x8)
    await take_trap(dut, cause=3, pc=0x40, tval=0)
    await take_mret(dut)
    # MIE = old MPIE, MPIE = 1
    check_equal(await read(dut, MSTATUS), 0x1888)
    # trap with MIE clear: MPIE becomes 0, and MRET brings MIE back to 0
    await access(dut, MSTATUS, RC, 0x8)
    await take_trap(dut, cause=2, pc=0x44, tval=0)
    check_equal(await read(dut, MSTATUS), 0x1800)
    await take_mret(dut)
    check_equal(await read(dut, MSTATUS), 0x1880)


@cocotb.test()
async def test_trap_aligns_mepc(dut):
    """Verifica trap aligns mepc."""
    await _reset(dut)
    await take_trap(dut, cause=0, pc=0x1003, tval=0x1002)
    check_equal(await read(dut, MEPC), 0x1000)
