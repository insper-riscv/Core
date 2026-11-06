"""Testes do modulo.

Prioridade das exceções síncronas (Tabela 17 do volume privilegiado) e
espaço de endereços dos CSRs do modo máquina.

Uma instrução ilegal prevalece sobre o desalinhamento de alvo de salto,
mesmo quando a codificação reservada é de salto ou desvio com alvo
desalinhado. Os CSRs que o núcleo não tem (depuração 0x7B0 a 0x7BF,
gatilhos 0x7A0 a 0x7A3, mseccfg, menvcfg, mcounteren, medeleg, mideleg e
PMP) geram instrução ilegal, e a escrita nos de identificação também.

O tratador registra mcause e mtval de cada trap e retoma depois da
instrução.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import (
    MCAUSE,
    MEPC,
    MRET,
    MTVEC,
    NOP,
    csrrs,
    csrrw,
)
from tests.python.unittests.cores.sdram_stall import (
    _b,
    _i,
    addi,
    jal_self,
    lui,
    sw,
)

LOG_BASE = RAM_BASE + 0x100
HANDLER_WORD = 128
MTVAL = 0x343
CAUSE_ILLEGAL = 2


def csrrc(rd, csr, rs1):
    """Monta csrrc."""
    return (csr << 20) | (rs1 << 15) | (3 << 12) | (rd << 7) | 0x73


def csrrwi(rd, csr, imm):
    """Monta csrrwi."""
    return (csr << 20) | (imm << 15) | (5 << 12) | (rd << 7) | 0x73


# Cada caso é (palavra, causa esperada, mtval esperado); a causa None é
# uma instrução legal, que não pode gerar trap.
CASES = [
    # Codificações reservadas de salto e desvio com alvo desalinhado: a
    # causa é 2 (ilegal), nunca 0 (desalinhado).
    (_i(0x67, 0, 1, 2, 0), 2, 0),  # jalr funct3 = 001, rs1 = 6
    (_i(0x67, 0, 7, 2, 0), 2, 0),  # jalr funct3 = 111, rs1 = 6
    (_b(0b010, 2, 2, 6), 2, 0),  # branch funct3 = 010, rs1 = rs2
    (_b(0b010, 2, 3, 6), 2, 0),  # branch funct3 = 010, rs1 != rs2
    (_b(0b011, 2, 2, 6), 2, 0),  # branch funct3 = 011, rs1 = rs2
    (_b(0b011, 2, 3, 6), 2, 0),  # branch funct3 = 011, rs1 != rs2
    # CSRs que o núcleo não tem.
    (csrrw(0, 0x7A0, 2), 2, 0),  # tselect
    (csrrs(6, 0x7A1, 0), 2, 0),  # tdata1, só leitura
    (csrrs(6, 0x7B0, 0), 2, 0),  # dcsr
    (csrrw(0, 0x7B1, 2), 2, 0),  # dpc
    (csrrs(6, 0x7B2, 0), 2, 0),  # dscratch0
    (csrrs(6, 0x7B3, 0), 2, 0),  # dscratch1
    (csrrs(6, 0x7B7, 0), 2, 0),  # reservado do modo de depuração
    (csrrs(6, 0x7BF, 0), 2, 0),  # último do bloco de depuração
    (csrrs(6, 0x747, 0), 2, 0),  # mseccfg
    (csrrs(6, 0x30A, 0), 2, 0),  # menvcfg
    (csrrs(6, 0x306, 0), 2, 0),  # mcounteren
    (csrrs(6, 0x302, 0), 2, 0),  # medeleg
    (csrrs(6, 0x303, 0), 2, 0),  # mideleg
    (csrrs(6, 0x3A0, 0), 2, 0),  # pmpcfg0
    (csrrs(6, 0x3B0, 0), 2, 0),  # pmpaddr0
    (csrrs(6, 0x34A, 0), 2, 0),  # mtinst
    (csrrs(6, 0x34B, 0), 2, 0),  # mtval2
    (csrrs(6, 0x100, 0), 2, 0),  # sstatus
    (csrrs(6, 0x180, 0), 2, 0),  # satp
    (csrrs(6, 0x800, 0), 2, 0),  # CSR de uso personalizado (0x800)
    (csrrs(6, 0xFFF, 0), 2, 0),  # último endereço
    # Escrita em CSR de identificação (somente leitura).
    (csrrw(0, 0xF11, 2), 2, 0),  # mvendorid
    (csrrs(0, 0xF12, 2), 2, 0),  # marchid, csrrs com rs1 != 0
    (csrrc(0, 0xF13, 2), 2, 0),  # mimpid, csrrc com rs1 != 0
    (csrrw(0, 0xF14, 0), 2, 0),  # mhartid, csrrw escreve mesmo com x0
    (csrrwi(0, 0xF15, 1), 2, 0),  # mconfigptr
    # Legais: leitura sem escrita nos de identificação, escrita em misa
    # (WARL, ignorada) e em mstatush (WARL, ignorada).
    (csrrs(6, 0xF11, 0), None, 0),
    (csrrs(6, 0xF12, 0), None, 0),
    (csrrs(6, 0xF13, 0), None, 0),
    (csrrs(6, 0xF14, 0), None, 0),
    (csrrs(6, 0xF15, 0), None, 0),
    (csrrw(0, 0x301, 2), None, 0),
    (csrrw(0, 0x310, 2), None, 0),
    (csrrs(6, 0x310, 0), None, 0),
]


def build():
    """Monta o programa."""
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        addi(2, 0, 6),
        addi(3, 0, 7),
        addi(10, 0, 0),
    ]
    for word, _cause, _tval in CASES:
        program += [word, addi(10, 10, 1)]
    program += [
        sw(10, 7, 4),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    check_true(len(program) < HANDLER_WORD, len(program))
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
    return program


@cocotb.test()
async def test_trap_priority_and_csr_space(dut):
    """Verifica a causa e o mtval de cada caso e que os legais não trapam."""
    ram = await run_program(dut, build(), max_cycles=12000)
    slot = 0
    for index, (_word, cause, tval) in enumerate(CASES):
        if cause is None:
            continue
        got = ram.get(LOG_BASE + 8 * slot)
        check_equal(got, cause, f"caso {index}: mcause {got}")
        got_tval = ram.get(LOG_BASE + 8 * slot + 4)
        check_equal(got_tval, tval, f"caso {index}: mtval {got_tval}")
        slot += 1
    check_true(
        LOG_BASE + 8 * slot not in ram, "uma instrução legal gerou trap"
    )
    check_equal(ram[RAM_BASE + 4], len(CASES), "o programa não retomou")
