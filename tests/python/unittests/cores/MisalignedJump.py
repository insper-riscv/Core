"""Testes do modulo.

Um salto tomado para um alvo desalinhado dispara a exceção de endereço
de instrução (mcause 0).

O alvo de um salto é desalinhado quando o seu bit 1 vale '1' (o bit 0 é
sempre zero). No JALR esse bit sai da soma de rs1 com o imediato,
inclusive com vai-um vindo do bit 0; no desvio, do somador de PC mais
imediato. O tratador registra mcause e mtval de cada exceção e retoma
depois da instrução; os saltos de alvo alinhado e o desvio não tomado
não podem disparar exceção.
"""

import cocotb

from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.IllegalInstruction import (
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
from tests.python.unittests.cores.SdramStall import (
    _b,
    _i,
    addi,
    jal_self,
    lui,
    sw,
)

MTVAL = 0x343
JALR = 0x67
# Somas rs1 + imm testadas, em relação ao endereço do JALR; o alvo é a
# soma com o bit 0 zerado.
SUM_OFFSETS = (4, 5, 6, 7)
IMMEDIATES = (0, 1, 2, 3, -1)
BEQ, BNE = 0b000, 0b001
BRANCH_MISALIGNED_OFFSET = 6
HEADER_WORDS = 10


def build_program():
    """Executa build program.

    Monta o programa e devolve também as exceções esperadas como
    (mcause, mtval).
    """
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        NOP,
        NOP,
        NOP,
        NOP,
    ]
    assert len(program) == HEADER_WORDS
    expected = []
    for offset in SUM_OFFSETS:
        for imm in IMMEDIATES:
            # O addi que carrega rs1 vem antes do JALR, que fica uma
            # palavra depois.
            jalr_address = 4 * len(program) + 4
            total = jalr_address + offset
            program.append(addi(6, 0, total - imm))
            program.append(_i(JALR, 0, 0, 6, imm))
            if (total & ~1) & 2:
                expected.append((0, total & ~1))
    # Desvio tomado para um alvo desalinhado dispara a exceção; o mesmo
    # desvio não tomado não dispara.
    branch_address = 4 * len(program)
    program.append(_b(BEQ, 0, 0, BRANCH_MISALIGNED_OFFSET))
    expected.append((0, branch_address + BRANCH_MISALIGNED_OFFSET))
    program.append(_b(BNE, 0, 0, BRANCH_MISALIGNED_OFFSET))
    program += [
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    assert len(program) < HANDLER_WORD
    program += [NOP] * (HANDLER_WORD - len(program))
    program += [
        csrrs(6, MCAUSE, 0),
        sw(6, 11, 0),
        csrrs(6, MTVAL, 0),
        sw(6, 11, 4),
        addi(11, 11, 8),
        csrrs(8, MEPC, 0),
        addi(8, 8, 4),
        csrrw(0, MEPC, 8),
        MRET,
    ]
    return program, expected


@cocotb.test()
async def test_misaligned_jump_targets_trap(dut):
    """Verifica misaligned jump targets trap.

    Cada alvo desalinhado gera uma exceção com mcause 0 e mtval igual ao
    alvo; os alinhados não geram.
    """
    program, expected = build_program()
    ram = await run_program(dut, program, max_cycles=6000)
    seen = []
    address = LOG_BASE
    while address in ram:
        seen.append((ram[address], ram[address + 4]))
        address += 8
    assert seen == expected, (
        f"exceções registradas {seen}, esperadas {expected}"
    )
