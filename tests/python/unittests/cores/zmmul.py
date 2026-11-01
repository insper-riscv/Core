"""Testes do modulo.

With only the Zmmul extension the four multiplications run and the four
divisions trap.

DIV, DIVU, REM and REMU have no owner, so they are illegal instructions:
mcause 2, the destination is not written, and the program resumes after
each one.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import (
    HANDLER_WORD,
    LOG_BASE,
    MCAUSE,
    MEPC,
    MRET,
    MTVEC,
    NOP,
    csrrs,
    csrrw,
)
from tests.python.unittests.cores.sdram_stall import (
    _r,
    addi,
    jal_self,
    lui,
    sw,
)

MULDIV_FUNCT7 = 0x01
MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU = range(8)
DIVISIONS = [DIV, DIVU, REM, REMU]
PRODUCTS = [MUL, MULH, MULHSU, MULHU]
A, B = -6, 7
UNSIGNED_A = A & 0xFFFFFFFF
EXPECTED = {
    MUL: (A * B) & 0xFFFFFFFF,
    MULH: ((A * B) >> 32) & 0xFFFFFFFF,
    MULHSU: ((A * B) >> 32) & 0xFFFFFFFF,
    MULHU: (UNSIGNED_A * B) >> 32,
}
RESULT_WORD = {MUL: 2, MULH: 3, MULHSU: 4, MULHU: 5}
UNTOUCHED = 0x55


def build():
    """Executa build."""
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        addi(9, 0, UNTOUCHED),
        addi(2, 0, A),
        addi(3, 0, B),
        addi(10, 0, 0),
    ]
    for funct3 in DIVISIONS:
        program += [_r(9, funct3, 2, 3, MULDIV_FUNCT7), addi(10, 10, 1)]
    for funct3 in PRODUCTS:
        program += [
            _r(4, funct3, 2, 3, MULDIV_FUNCT7),
            sw(4, 7, 4 * RESULT_WORD[funct3]),
        ]
    program += [
        sw(9, 7, 0),
        sw(10, 7, 4),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
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
async def test_zmmul_multiplies_and_traps_on_division(dut):
    """Verifica zmmul multiplies and traps on division.

    The products are exact, each division traps once with cause 2 and
    writes nothing.
    """
    ram = await run_program(dut, build(), max_cycles=4000)
    for i in range(len(DIVISIONS)):
        check_equal(
            ram.get(LOG_BASE + 4 * i),
            2,
            f"division {i}: mcause {ram.get(LOG_BASE + 4 * i)}",
        )
    check_true(
        LOG_BASE + 4 * len(DIVISIONS) not in ram, "a multiplication trapped"
    )
    check_equal(ram[RAM_BASE], UNTOUCHED, "a division wrote its destination")
    check_equal(
        ram[RAM_BASE + 4],
        len(DIVISIONS),
        "the program did not resume after each trap",
    )
    for funct3 in PRODUCTS:
        got = ram[RAM_BASE + 4 * RESULT_WORD[funct3]]
        check_equal(
            got,
            EXPECTED[funct3],
            f"funct3 {funct3}: {got:#x} != {EXPECTED[funct3]:#x}",
        )
