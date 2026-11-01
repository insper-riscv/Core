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


RECORD = [None]


async def _reset(dut):
    RECORD[0] = None
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
    """The stall is 35 cycles for a multiplication and 37 for a division (operands never repeat)."""
    await _reset(dut)
    for i, (funct3, want) in enumerate(((0, 35), (3, 35), (4, 37), (7, 37))):
        _, stalled = await execute(dut, funct3, 12345 + i, 678)
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


FUSED_STALL = 3


def is_mult(funct3):
    return funct3 < 4


def full_stall(funct3, a, b):
    """Stall cycles of an operation that runs in full: a division by zero or an overflow is short."""
    if is_mult(funct3):
        return 35
    special = b == 0 or (funct3 in (4, 6) and a == 0x80000000 and b == 0xFFFFFFFF)
    return 4 if special else 37


def fuses(record, funct3, a, b):
    """The model of the fusion rule: same values, same family, another operation."""
    if record is None:
        return False
    ra, rb, rf = record
    if (a, b) != (ra, rb) or funct3 == rf:
        return False
    if is_mult(funct3) != is_mult(rf):
        return False
    return is_mult(funct3) or (funct3 & 1) == (rf & 1)


async def run_sequence(dut, ops, gap):
    """Run (funct3, a, b) in order, checking the value and the length of every stall."""
    fused_count = 0
    for funct3, a, b in ops:
        want_fused = fuses(RECORD[0], funct3, a, b)
        got, stalled = await execute(dut, funct3, a, b)
        assert got == model(funct3, a, b), (
            f"{OPS[funct3]} {a:#010x}, {b:#010x}: got {got:#010x}, expected {model(funct3, a, b):#010x}"
        )
        want_stall = FUSED_STALL if want_fused else full_stall(funct3, a, b)
        assert stalled == want_stall, (
            f"{OPS[funct3]} {a:#010x}, {b:#010x} stalled {stalled} cycles, expected {want_stall}"
        )
        if want_fused:
            fused_count += 1
        else:
            RECORD[0] = (a, b, funct3)
        await retire(dut, gap)
    return fused_count


PAIRS = (
    (1, 0), (0, 1), (2, 0), (0, 2), (3, 0), (0, 3), (1, 2), (2, 1), (1, 3), (3, 1), (2, 3), (3, 2),
    (4, 6), (6, 4), (5, 7), (7, 5),
)
VALUES = (
    (0x12345678, 0x9ABCDEF0),
    (0xFFFFFFFB, 7),
    (7, 0xFFFFFFFB),
    (0x80000000, 0xFFFFFFFF),
    (0x80000000, 0x80000000),
    (0xFFFFFFFF, 0xFFFFFFFF),
    (100, 0),
    (0, 100),
)


@cocotb.test()
async def test_every_recommended_pair_fuses(dut):
    """Each pair of a family, in both orders, runs once: the second costs 3 stall cycles."""
    await _reset(dut)
    for gap in (0, 1):
        for first, second in PAIRS:
            for a, b in VALUES:
                count = await run_sequence(dut, [(first, a, b), (second, a, b)], gap)
                assert count == 1, f"{OPS[first]} then {OPS[second]} {a:#x}, {b:#x} did not fuse"
                await retire(dut, 0)


@cocotb.test()
async def test_what_does_not_fuse(dut):
    """A repeat of the same operation, other values, another family or another sign mode runs in full."""
    await _reset(dut)
    a, b = 0xFFFFFFF1, 7
    cases = [
        [(4, a, b), (4, a, b)],
        [(0, a, b), (0, a, b)],
        [(4, a, b), (6, a, b + 1)],
        [(4, a, b), (6, a + 1, b)],
        [(4, a, b), (7, a, b)],
        [(5, a, b), (6, a, b)],
        [(0, a, b), (4, a, b)],
        [(4, a, b), (1, a, b)],
        [(1, a, b), (6, a, b)],
    ]
    for ops in cases:
        # an unrelated operation first, so that the record of the previous case is gone
        await run_sequence(dut, [(0, 0x1111, 0x2222)], 1)
        assert await run_sequence(dut, ops, 1) == 0, ops
        await retire(dut, 0)


@cocotb.test()
async def test_another_operation_in_between_breaks_the_pair(dut):
    """The record holds the last operation only: DIV, MUL, REM with the same values runs the REM in full."""
    await _reset(dut)
    ops = [(4, 1000, 7), (0, 1000, 7), (6, 1000, 7)]
    assert await run_sequence(dut, ops, 1) == 0
    ops = [(4, 55, 7), (0, 1000, 9), (6, 55, 7)]
    assert await run_sequence(dut, ops, 1) == 0


@cocotb.test()
async def test_fused_operation_keeps_the_record(dut):
    """After a fused pair the record still holds the first operation: three operations fuse twice."""
    await _reset(dut)
    ops = [(1, 0x89ABCDEF, 0x1234567), (0, 0x89ABCDEF, 0x1234567), (2, 0x89ABCDEF, 0x1234567)]
    assert await run_sequence(dut, ops, 1) == 2


@cocotb.test()
async def test_random_sequences_repeat_values(dut):
    """Random operations over a few repeated values match the model, in value and in stall length."""
    await _reset(dut)
    rng = random.Random(11)
    pool = [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(3)] + [(EDGES[3], EDGES[4]), (9, 0)]
    fused = 0
    for _ in range(25):
        ops = []
        for _ in range(8):
            a, b = rng.choice(pool)
            ops.append((rng.randrange(8), a, b))
        fused += await run_sequence(dut, ops, rng.choice((0, 1)))
    assert fused > 10, "the random sequences never reached the fusion"
