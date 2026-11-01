"""Testes do modulo.

The M extension on the whole core: every operation, edge operands,
results chained by forwarding.

Each pair (a, b) runs the eight operations of RV32M in sequence, so the
M instructions follow each other without a gap, and then a MUL whose
result a REM uses at once.
"""

import cocotb

from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.SdramStall import _r, addi, jal_self, lui, sw

MASK = 0xFFFFFFFF
PAIRS = (
    (7, 3),
    (-7 & MASK, 3),
    (7, -3 & MASK),
    (0x80000000, MASK),
    (0x12345678, 0),
    (MASK, MASK),
    (100000, 70000),
    (0x80000000, 2),
)
DONE_OFFSET = DONE_ADDR - RAM_BASE
OPS = ("mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu")


def li(rd, value):
    """Lui + addi for a 32-bit constant."""
    upper = ((value + 0x800) >> 12) & 0xFFFFF
    lower = (value - (upper << 12)) & 0xFFF
    return [
        lui(rd, upper),
        addi(rd, rd, lower - 0x1000 if lower >= 0x800 else lower),
    ]


def signed(x):
    """Executa signed."""
    return x - (1 << 32) if x >> 31 else x


def model(op, a, b):  # complexipy: ignore
    """Return the RV32M result of the operation, as a 32-bit pattern."""
    sa, sb = signed(a), signed(b)
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


FUNCT3 = {op: i for i, op in enumerate(OPS)}


def m_op(op, rd, rs1, rs2):
    """Executa m op."""
    return _r(0x33, rd, FUNCT3[op], rs1, rs2, 1)


def build():
    """Executa build."""
    program = [addi(0, 0, 0), lui(7, RAM_BASE >> 12)]
    expected = {}
    offset = 0
    for a, b in PAIRS:
        program += li(1, a) + li(2, b)
        for op in OPS:
            program += [m_op(op, 3, 1, 2), sw(3, 7, offset)]
            expected[RAM_BASE + offset] = model(op, a, b)
            offset += 4
        # the REM reads the MUL result of the instruction right before
        # it
        program += [
            m_op("mul", 4, 1, 2),
            m_op("rem", 5, 4, 2),
            sw(5, 7, offset),
        ]
        expected[RAM_BASE + offset] = model("rem", model("mul", a, b), b)
        offset += 4
    assert offset < DONE_OFFSET
    program += [addi(14, 0, 1), sw(14, 7, DONE_OFFSET), jal_self()]
    return program, expected


@cocotb.test()
async def test_every_operation(dut):
    """Verifica every operation.

    All eight RV32M operations on edge operands, with and without
    forwarding.
    """
    program, expected = build()
    ram = await run_program(dut, program, max_cycles=20000)
    for addr, want in expected.items():
        assert ram.get(addr) == want, (
            f"RAM[0x{addr:08X}] = {ram.get(addr, 0):#x}, expected {want:#x}"
        )
