"""Testes do modulo.

Zihintntl e Zihintpause no nucleo: as cinco dicas executam como nop.

Cada dica roda com valores nao nulos nos registradores x2 a x5 e em x0,
e nenhum registrador muda nem ha excecao. O resultado e guardado logo
depois, e um tratador conta qualquer excecao.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import (
    MEPC,
    MRET,
    MTVEC,
    NOP,
    csrrs,
    csrrw,
)
from tests.python.unittests.cores.sdram_stall import (
    addi,
    jal_self,
    lui,
    sw,
)

HANDLER_WORD = 128
RESULT_BASE = 0x200
COUNT_OFFSET = 0x100
PAUSE = 0x0100000F
NTL_HINTS = (0x00200033, 0x00300033, 0x00400033, 0x00500033)
HINTS = (*NTL_HINTS, PAUSE)
VALUES = {2: 0x22, 3: 0x33, 4: 0x44, 5: 0x55}
CANARY = 0x7B


def build():
    """Build the program: each hint, then every register is stored."""
    program = [
        NOP,
        lui(7, RAM_BASE >> 12),
        addi(13, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 13),
        addi(6, 0, CANARY),
    ]
    program += [addi(reg, 0, val) for reg, val in VALUES.items()]
    for word in HINTS:
        program.append(word)
        # Back-to-back use of the registers the hint reads.
        program.append(sw(2, 7, RESULT_BASE))
    for reg in (2, 3, 4, 5, 6, 0):
        program.append(sw(reg, 7, RESULT_BASE + 4 * (reg + 1)))
    program += [
        sw(12, 7, COUNT_OFFSET),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    check_true(len(program) < HANDLER_WORD, len(program))
    program += [NOP] * (HANDLER_WORD - len(program))
    return program + [
        addi(12, 12, 1),
        csrrs(10, MEPC, 0),
        addi(10, 10, 4),
        csrrw(0, MEPC, 10),
        MRET,
    ]


@cocotb.test()
async def test_hints_execute_as_nop(dut):
    """Verifica hints execute as nop.

    No register changes, x0 stays zero and no exception is counted.
    """
    ram = await run_program(dut, build(), max_cycles=3000)
    check_equal(ram.get(RAM_BASE + COUNT_OFFSET), 0, "an exception")
    check_equal(ram.get(RAM_BASE + RESULT_BASE), VALUES[2], "x2 after hint")
    want = {**VALUES, 6: CANARY, 0: 0}
    for reg, value in want.items():
        got = ram.get(RAM_BASE + RESULT_BASE + 4 * (reg + 1))
        check_equal(got, value, f"x{reg}: {got}")
