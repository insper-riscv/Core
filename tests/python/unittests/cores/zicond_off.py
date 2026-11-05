"""Testes do modulo.

Sem a extensao Zicond, czero.eqz e czero.nez sao instrucoes ilegais.

Cada uma gera mcause 2, nao escreve o registrador de destino e o
programa continua depois dela. O tratador registra o mcause e retoma a
execucao na instrucao seguinte.
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
    addi,
    jal_self,
    lui,
    sw,
)
from tests.python.unittests.cores.zicond import EQZ, NEZ, czero

UNTOUCHED = 0x55
ENCODINGS = [(EQZ, 2, 3), (NEZ, 2, 3), (EQZ, 0, 0), (NEZ, 9, 9)]


def build():
    """Monta o programa e o tratador de excecao."""
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        addi(9, 0, UNTOUCHED),
        addi(2, 0, 6),
        addi(3, 0, 7),
        addi(10, 0, 0),
    ]
    for funct3, rs1, rs2 in ENCODINGS:
        program += [czero(funct3, 9, rs1, rs2), addi(10, 10, 1)]
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
async def test_zicond_is_illegal_when_off(dut):
    """Verifica que as duas instrucoes geram excecao de ilegal.

    Cada uma da causa 2 uma vez, nada e escrito e o programa retoma.
    """
    ram = await run_program(dut, build(), max_cycles=4000)
    for i in range(len(ENCODINGS)):
        got = ram.get(LOG_BASE + 4 * i)
        check_equal(got, 2, f"instrucao {i}: mcause {got}")
    check_true(LOG_BASE + 4 * len(ENCODINGS) not in ram, "trap a mais")
    check_equal(ram[RAM_BASE], UNTOUCHED, "uma instrucao escreveu rd")
    check_equal(ram[RAM_BASE + 4], len(ENCODINGS), "o programa nao retomou")
