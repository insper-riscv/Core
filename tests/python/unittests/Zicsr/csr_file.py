"""csr_file: Zicsr read/modify/write semantics and the machine-mode CSR bank."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

RW, RS, RC = 0b001, 0b010, 0b011
MSTATUS, MISA, MIE, MTVEC, MSTATUSH = 0x300, 0x301, 0x304, 0x305, 0x310
MSCRATCH, MEPC, MCAUSE, MTVAL, MIP = 0x340, 0x341, 0x342, 0x343, 0x344
MVENDORID, MARCHID, MIMPID, MHARTID, MCONFIGPTR = 0xF11, 0xF12, 0xF13, 0xF14, 0xF15


async def _reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.commit.value = 0
    dut.addr.value = MSCRATCH
    dut.op.value = RS
    dut.wdata.value = 0
    dut.src_zero.value = 1
    dut.reset.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)


async def access(dut, addr, op, wdata=0, src_zero=None, commit=1):
    """One CSR instruction: returns (old value, illegal) seen before the write lands."""
    dut.addr.value = addr
    dut.op.value = op
    dut.wdata.value = wdata
    dut.src_zero.value = int(wdata == 0) if src_zero is None else src_zero
    dut.commit.value = commit
    await Timer(1, unit="ns")
    seen = int(dut.rdata.value), int(dut.illegal.value)
    await RisingEdge(dut.clk)
    dut.commit.value = 0
    await Timer(1, unit="ns")
    return seen


async def read(dut, addr):
    return (await access(dut, addr, RS, 0))[0]


@cocotb.test()
async def test_reset_values(dut):
    await _reset(dut)
    want = {MSTATUS: 0x1800, MISA: 0x40001100, MIE: 0, MTVEC: 0, MSTATUSH: 0, MSCRATCH: 0,
            MEPC: 0, MCAUSE: 0, MTVAL: 0, MIP: 0, MVENDORID: 0, MARCHID: 0, MIMPID: 0,
            MHARTID: 0, MCONFIGPTR: 0}
    for addr, value in want.items():
        assert await read(dut, addr) == value, f"{addr:#x}"


@cocotb.test()
async def test_csrrw_swaps(dut):
    await _reset(dut)
    assert (await access(dut, MSCRATCH, RW, 0xDEADBEEF)) == (0, 0)
    assert (await access(dut, MSCRATCH, RW, 0x12345678)) == (0xDEADBEEF, 0)
    assert await read(dut, MSCRATCH) == 0x12345678


@cocotb.test()
async def test_csrrs_csrrc_bit_ops(dut):
    await _reset(dut)
    await access(dut, MSCRATCH, RW, 0x0000FF00)
    assert (await access(dut, MSCRATCH, RS, 0x000000F0))[0] == 0x0000FF00
    assert await read(dut, MSCRATCH) == 0x0000FFF0
    assert (await access(dut, MSCRATCH, RC, 0x00000FF0))[0] == 0x0000FFF0
    assert await read(dut, MSCRATCH) == 0x0000F000


@cocotb.test()
async def test_set_clear_with_zero_source_does_not_write(dut):
    """CSRRS/CSRRC with rs1 = x0 read only; a zero value from a register still writes nothing."""
    await _reset(dut)
    await access(dut, MSCRATCH, RW, 0xA5A5A5A5)
    await access(dut, MSCRATCH, RS, 0, src_zero=1)
    await access(dut, MSCRATCH, RC, 0, src_zero=1)
    assert await read(dut, MSCRATCH) == 0xA5A5A5A5
    # CSRRW with a zero source writes zero (RW always writes).
    await access(dut, MSCRATCH, RW, 0, src_zero=1)
    assert await read(dut, MSCRATCH) == 0


@cocotb.test()
async def test_no_commit_no_write(dut):
    """A stalled instruction (commit = 0) leaves the CSR alone."""
    await _reset(dut)
    await access(dut, MSCRATCH, RW, 0x1111, commit=0)
    assert await read(dut, MSCRATCH) == 0


@cocotb.test()
async def test_field_masks(dut):
    await _reset(dut)
    await access(dut, MSTATUS, RW, 0xFFFFFFFF)
    assert await read(dut, MSTATUS) == 0x1888  # MPP = 11, MPIE and MIE set, rest zero
    await access(dut, MSTATUS, RW, 0)
    assert await read(dut, MSTATUS) == 0x1800
    await access(dut, MTVEC, RW, 0x80000003)
    assert await read(dut, MTVEC) == 0x80000000  # mode fixed at direct
    await access(dut, MEPC, RW, 0x80000003)
    assert await read(dut, MEPC) == 0x80000000  # IALIGN = 32
    await access(dut, MCAUSE, RW, 0xFFFFFFFF)
    await access(dut, MTVAL, RW, 0xFFFFFFFF)
    assert await read(dut, MCAUSE) == 0xFFFFFFFF
    assert await read(dut, MTVAL) == 0xFFFFFFFF
    for addr in (MIE, MSTATUSH):
        await access(dut, addr, RW, 0xFFFFFFFF)
        assert await read(dut, addr) == 0, f"{addr:#x}"


@cocotb.test()
async def test_read_only_csrs(dut):
    """An effective write to a read-only CSR is illegal and changes nothing; a read is fine."""
    await _reset(dut)
    for addr in (MISA, MIP, MVENDORID, MARCHID, MIMPID, MHARTID, MCONFIGPTR):
        old, illegal = await access(dut, addr, RW, 0xFFFFFFFF)
        want_illegal = int(addr >> 10 == 0b11)
        assert illegal == want_illegal, f"{addr:#x} write"
        old, illegal = await access(dut, addr, RS, 0, src_zero=1)
        assert illegal == 0, f"{addr:#x} read"
    assert await read(dut, MISA) == 0x40001100
    assert await read(dut, MIP) == 0


@cocotb.test()
async def test_unknown_csr_is_illegal(dut):
    await _reset(dut)
    for addr in (0x000, 0x100, 0x302, 0x303, 0x306, 0x320, 0x7A0, 0xB00, 0xC00, 0xF10, 0xFFF):
        assert (await access(dut, addr, RS, 0, src_zero=1))[1] == 1, f"{addr:#x}"
