"""Testes do modulo.

mtvec no modo vetorado: a interrupção de causa c vai a BASE + 4 x c
(software em 12, timer em 28, externa em 44), e toda exceção síncrona
vai a BASE, inclusive o ecall, que tem causa 11 mas não é interrupção.
O programa troca para o modo vetorado, deixa as três linhas subirem
juntas e confere em que entrada da tabela cada trap caiu.
"""

import cocotb

from tests.python.unittests.checks import Prng, check_equal, check_true
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
from tests.python.unittests.cores.irq_common import (
    ACK_BASE,
    EXTERNAL,
    LOG_BASE,
    MIE,
    MIE_BIT,
    MSTATUS,
    RESULT_BASE,
    SOFTWARE,
    TIMER,
    Lines,
    Program,
    check_count,
    csrrsi,
    emit_ecall,
    emit_inc,
    emit_mul,
    jal,
    load_immediate,
    read_log,
)
from tests.python.unittests.cores.sdram_stall import addi, jal_self, sw

TABLE = 0x1000
HANDLERS = 0x1100
ID_EXCEPTION, ID_BAD = 0x100, 0x7FF
SLOTS = {3: SOFTWARE, 7: TIMER, 11: EXTERNAL}
ACK_OFFSET = {3: 12, 7: 28, 11: 44}
GROUPS = (emit_inc, emit_ecall, emit_mul, emit_inc)
IRQ_ORDER = [11, 3, 7]


def irq_handler(ident, ack):
    """Entrada de interrupção: registra, reconhece a linha e retorna."""
    return [
        addi(29, 0, ident),
        sw(29, 28, 0),
        csrrs(30, MEPC, 0),
        sw(30, 28, 4),
        sw(10, 28, 8),
        addi(28, 28, 12),
        sw(0, 27, ack),
        MRET,
    ]


def exception_handler():
    """Entrada de exceção: registra, pula a instrução e retorna."""
    return [
        addi(29, 0, ID_EXCEPTION),
        sw(29, 28, 0),
        csrrs(30, MEPC, 0),
        sw(30, 28, 4),
        sw(10, 28, 8),
        addi(28, 28, 12),
        addi(30, 30, 4),
        csrrw(0, MEPC, 30),
        MRET,
    ]


def bad_handler():
    """Entrada que nenhum trap deve alcançar."""
    return [
        addi(29, 0, ID_BAD),
        sw(29, 28, 0),
        csrrs(30, MCAUSE, 0),
        sw(30, 28, 4),
        sw(10, 28, 8),
        addi(28, 28, 12),
        MRET,
    ]


def build(seed, groups=90):
    """Monta o programa, a tabela de vetores e os tratadores."""
    prog = Program(0)
    prog.emit(NOP)
    for word in load_immediate(5, TABLE | 1):
        prog.emit(word)
    prog.emit(csrrw(0, MTVEC, 5))
    prog.emit(csrrs(6, MTVEC, 0))
    for reg, value in ((7, RAM_BASE), (27, ACK_BASE), (28, LOG_BASE)):
        for word in load_immediate(reg, value):
            prog.emit(word)
    prog.emit(sw(6, 7, RESULT_BASE - RAM_BASE))
    prog.emit(addi(14, 0, 1))
    prog.emit(addi(15, 0, 1))
    for word in load_immediate(5, SOFTWARE | TIMER | EXTERNAL):
        prog.emit(word)
    prog.emit(csrrs(0, MIE, 5))
    prog.emit(csrrsi(0, MSTATUS, MIE_BIT))
    rng = Prng(seed)
    for _ in range(groups):
        GROUPS[rng.getrandbits(8) % len(GROUPS)](prog)
    prog.emit(sw(10, 7, RESULT_BASE - RAM_BASE + 4))
    prog.emit(sw(14, 7, DONE_ADDR - RAM_BASE))
    prog.emit(jal_self())
    check_true(prog.pc < TABLE)
    return prog


def memory_image(prog):
    """Imagem de memória: programa, tabela de vetores e tratadores."""
    imem = {4 * i: word for i, word in enumerate(prog.words)}
    entries: dict[int | str, list[int]] = {0: exception_handler()}
    entries.update({c: irq_handler(c, ACK_OFFSET[c]) for c in SLOTS})
    entries["bad"] = bad_handler()
    address = HANDLERS
    target = {}
    for key, words in entries.items():
        target[key] = address
        imem.update({address + 4 * i: w for i, w in enumerate(words)})
        address += 4 * len(words)
    for slot in range(16):
        destination = target.get(slot, target["bad"])
        imem[TABLE + 4 * slot] = jal(0, destination - (TABLE + 4 * slot))
    return imem


@cocotb.test()
async def test_vectored_entry_points(dut):
    """Verifica BASE + 4 x causa nas interrupções, BASE nas exceções."""
    prog = build(0xABCD)
    lines = Lines((SOFTWARE, TIMER, EXTERNAL), (4, 11, 2, 19, 7, 0), masked=())
    ram = await run_program(
        dut, [], imem=memory_image(prog), monitor=lines, max_cycles=12000
    )
    check_equal(ram[RESULT_BASE], TABLE | 1, "leitura de mtvec")
    entries = read_log(ram)
    irqs = [ident for ident, _, _ in entries if ident != ID_EXCEPTION]
    check_true(ID_BAD not in irqs, "vetor errado")
    check_count(irqs, 30)
    check_equal(irqs, (IRQ_ORDER * len(irqs))[: len(irqs)])
    faults = list(prog.kinds.values()).count("ecall")
    seen = len(entries) - len(irqs)
    check_equal(seen, faults, "ecall fora da entrada BASE")
    for ident, epc, snapshot in entries:
        check_equal(snapshot, prog.expected[epc], f"x10 em {epc:#x}")
        if ident == ID_EXCEPTION:
            check_equal(prog.kinds[epc], "ecall", "exceção fora de ecall")
    check_equal(ram[RESULT_BASE + 4], prog.count)
