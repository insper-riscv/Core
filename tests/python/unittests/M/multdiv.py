"""multdiv: the eight RV32M operations behind the stall the core uses.

The test holds the operands and the funct3 the way EX does: the instruction stays
asserted while the stall is up and for the one cycle in which the stall is already
down, and the next instruction replaces it on the following edge.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

MASK = 0xFFFFFFFF
TIMEOUT_CYCLES = 100
OPS = ("mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu")
EDGES = (0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF)


def _signed(value):
    return value - (1 << 32) if value >> 31 else value


def model(funct3, a, b):
    """The RV32M result of the operation, as a 32-bit pattern."""
    op = OPS[funct3]
    sa, sb = _signed(a), _signed(b)
    if op == "mul":
        return (a * b) & MASK
    if op == "mulh":
        return ((sa * sb) >> 32) & MASK
    if op == "mulhsu":
        return ((sa * b) >> 32) & MASK
    if op == "mulhu":
        return ((a * b) >> 32) & MASK
    if b == 0:
        return MASK if op in ("div", "divu") else a
    if op in ("divu", "remu"):
        return (a // b if op == "divu" else a % b) & MASK
    if sa == -(1 << 31) and sb == -1:
        return 0x80000000 if op == "div" else 0
    quotient = abs(sa) // abs(sb)
    if (sa < 0) != (sb < 0):
        quotient = -quotient
    return (quotient if op == "div" else sa - quotient * sb) & MASK


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_valid.value = 0
    dut.i_is_muldiv.value = 0
    dut.i_funct3.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def execute(dut, funct3, a, b):
    """Present one instruction in EX; return (result, stalled cycles) once the stall is down.

    On return the instruction is still in EX for the cycle in which the stall fell, as in
    the core, and the clock has not yet reached the edge that moves it on.
    """
    dut.i_valid.value = 1
    dut.i_is_muldiv.value = 1
    dut.i_funct3.value = funct3
    dut.i_a.value = a
    dut.i_b.value = b
    await Timer(1, unit="ns")
    assert int(dut.o_stall.value) == 1, "the stall must rise in the first cycle"
    stalled = 0
    while int(dut.o_stall.value):
        stalled += 1
        assert stalled < TIMEOUT_CYCLES, "the stall never fell"
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    return int(dut.o_result.value), stalled


async def retire(dut, gap):
    """The edge that moves the instruction on; gap cycles of bubble follow it."""
    await RisingEdge(dut.i_clk)
    dut.i_valid.value = 0
    dut.i_is_muldiv.value = 0
    for _ in range(gap):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def _check(dut, funct3, pairs, gap):
    for a, b in pairs:
        got, _ = await execute(dut, funct3, a, b)
        want = model(funct3, a, b)
        assert got == want, f"{OPS[funct3]} {a:#010x}, {b:#010x}: got {got:#010x}, expected {want:#010x}"
        await retire(dut, gap)


@cocotb.test()
async def test_every_operation_on_edge_operands(dut):
    """The eight operations on every pair of edge operands, with a bubble between instructions."""
    await _reset(dut)
    for funct3 in range(8):
        await _check(dut, funct3, [(a, b) for a in EDGES for b in EDGES], gap=1)


@cocotb.test()
async def test_back_to_back(dut):
    """The next instruction starts on the edge after the previous one, with no bubble."""
    await _reset(dut)
    rng = random.Random(7)
    for _ in range(100):
        funct3 = rng.randrange(8)
        await _check(dut, funct3, [(rng.getrandbits(32), rng.getrandbits(32))], gap=0)


@cocotb.test()
async def test_stall_length(dut):
    """The stall is 35 cycles for a multiplication and 37 for a division."""
    await _reset(dut)
    for funct3, want in ((0, 35), (3, 35), (4, 37), (7, 37)):
        _, stalled = await execute(dut, funct3, 12345, 678)
        assert stalled == want, f"{OPS[funct3]} stalled {stalled} cycles, expected {want}"
        await retire(dut, 1)


@cocotb.test()
async def test_no_stall_without_a_valid_m_instruction(dut):
    """A bubble, or an instruction that is not M, never stalls."""
    await _reset(dut)
    for valid, is_muldiv in ((0, 1), (1, 0), (0, 0)):
        dut.i_valid.value = valid
        dut.i_is_muldiv.value = is_muldiv
        for _ in range(5):
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            assert int(dut.o_stall.value) == 0
