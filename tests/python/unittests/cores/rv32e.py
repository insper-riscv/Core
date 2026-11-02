"""Testes do modulo.

With num_regs = 16 the core is an RV32E: x0 to x15 work, and an
instruction that uses x16 to x31 as rd, rs1 or rs2 traps with mcause 2
and has no effect. The misa register announces the E base (bit 4) in
place of the I base (bit 8).

The handler logs mcause of each trap and resumes after the instruction.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.sdram_stall import (
    _b,
    _i,
    _r,
    _s,
    add,
    addi,
    jal_self,
    lui,
    sw,
)

LOG_BASE = RAM_BASE + 0x100
HANDLER_WORD = 64
MTVEC, MEPC, MCAUSE = 0x305, 0x341, 0x342
MISA = 0x301
SYSTEM = 0x73
MRET = 0x30200073
NOP = addi(0, 0, 0)


def csrrw(rd, csr, rs1):
    """Executa csrrw."""
    return (csr << 20) | (rs1 << 15) | (1 << 12) | (rd << 7) | SYSTEM


def csrrs(rd, csr, rs1):
    """Executa csrrs."""
    return (csr << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | SYSTEM


ILLEGAL = [
    addi(16, 0, 1),  # rd = x16
    addi(1, 16, 1),  # rs1 = x16
    add(1, 2, 31),  # rs2 = x31
    add(20, 2, 3),  # rd = x20
    _s(0b010, 2, 17, 0),  # sw with rs2 = x17
    _s(0b010, 18, 2, 0),  # sw with rs1 = x18
    _i(0x03, 1, 0b010, 19, 0),  # lw with rs1 = x19
    _b(0b000, 16, 2, 8),  # beq with rs1 = x16
    lui(31, 1),  # rd = x31
]
LEGAL = [
    addi(15, 0, 3),  # the last register of the RV32E
    add(14, 15, 15),
    _r(13, 0b000, 15, 14, 0x00),
    csrrs(12, MCAUSE, 0),
]


def build():
    """Executa build."""
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        addi(1, 0, 0x55),  # x1 must survive every illegal instruction
        addi(2, 0, 6),
        addi(3, 0, 7),
        addi(10, 0, 0),
    ]
    for word in ILLEGAL + LEGAL:
        program += [word, addi(10, 10, 1)]
    program += [
        sw(1, 7, 0),
        sw(10, 7, 4),
        sw(13, 7, 8),
        addi(9, 0, 1),
        sw(9, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    check_true(len(program) < HANDLER_WORD)
    program += [NOP] * (HANDLER_WORD - len(program))
    program += [
        csrrs(6, MCAUSE, 0),
        sw(6, 11, 0),
        addi(11, 11, 4),
        csrrs(8, MEPC, 0),
        addi(8, 8, 4),
        csrrw(0, MEPC, 8),
        MRET,
    ]
    return program


@cocotb.test()
async def test_registers_above_x15_trap(dut):
    """Verifica registers above x15 trap.

    Every use of x16 to x31 traps once with cause 2 and resumes after
    it, and x0 to x15 keep working.
    """
    ram = await run_program(dut, build(), max_cycles=4000)
    for i in range(len(ILLEGAL)):
        check_equal(
            ram.get(LOG_BASE + 4 * i),
            2,
            f"trap {i}: mcause {ram.get(LOG_BASE + 4 * i)}",
        )
    check_true(
        LOG_BASE + 4 * len(ILLEGAL) not in ram, "a legal instruction trapped"
    )
    check_equal(ram[RAM_BASE], 0x55, "an illegal instruction wrote x1")
    check_equal(
        ram[RAM_BASE + 4],
        len(ILLEGAL) + len(LEGAL),
        "the program did not resume after each trap",
    )
    check_equal(ram[RAM_BASE + 8], 9, "x13 = x15 + x14 = 3 + 6 is wrong")


@cocotb.test()
async def test_misa_announces_the_e_base(dut):
    """Verifica misa announces the e base.

    The E bit is set, the I bit is clear (the E bit is the complement of
    the I bit) and the M bit is set because the core has M.
    """
    program = [
        NOP,
        lui(7, RAM_BASE >> 12),
        csrrs(6, MISA, 0),
        sw(6, 7, 0),
        addi(9, 0, 1),
        sw(9, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    ram = await run_program(dut, program, max_cycles=400)
    misa = ram[RAM_BASE]
    check_equal(misa, 0x40001010, f"misa {misa:#010x}")
    check_true(misa & (1 << 4), "the E bit is clear")
    check_true(not misa & (1 << 8), "the I bit is set")
