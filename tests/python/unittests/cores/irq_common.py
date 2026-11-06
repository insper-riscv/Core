"""Montagem e verificação comuns dos testes de interrupção do núcleo.

Um programa de linha reta, sorteado por uma semente, soma 1 a x10 por
grupos de instruções de tipos variados (soma simples, multiplicação,
divisão, acesso desalinhado, escrita em CSR, desvios, ecall e
instrução ilegal). O tratador de interrupção registra mcause, mepc e x10
de cada entrada e reconhece a linha com um store. Como cada grupo soma
exatamente 1, o valor de x10 na entrada diz quantos grupos completaram:
ele precisa bater com o que o programa teria somado antes do endereço
guardado em mepc. Uma instrução repetida ou perdida muda a soma.
"""

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
from tests.python.unittests.cores.sdram_stall import (
    _b,
    _i,
    _r,
    addi,
    jal_self,
    lui,
    sw,
)

MSTATUS, MIE, MSCRATCH = 0x300, 0x304, 0x340
ECALL, EBREAK, WFI, FENCE_I = 0x73, 0x100073, 0x10500073, 0x100F
ILLEGAL_WORD = 0xFFFFFFFF
MIE_BIT = 0x8
SOFTWARE, TIMER, EXTERNAL = 1 << 3, 1 << 7, 1 << 11
CAUSE_SOFTWARE = 0x80000003
CAUSE_TIMER = 0x80000007
CAUSE_EXTERNAL = 0x8000000B
SDRAM_BASE = 0x40000000

LOG_BASE = RAM_BASE + 0x1000
ACK_BASE = RAM_BASE + 0x900
RESULT_BASE = RAM_BASE + 0x600
DATA_MISALIGNED = 0x300
DATA_COUNTER = 0x340
HANDLER_OFFSET = 0x1000
RESULT_COUNT = 6
PROGRESS_RETIRES = 2

# Registradores: x10 soma, x13 temporário, x14 e x15 valem 1, x19 e x20
# apontam os dados, x25 acumula erros, x26 conta exceções, x27 é a base
# dos reconhecimentos, x28 o ponteiro do registro, x29 e x30 são do
# tratador.
LINE_ADDRESS = {SOFTWARE: ACK_BASE + 12, TIMER: ACK_BASE + 28}
LINE_ADDRESS[EXTERNAL] = ACK_BASE + 44
LINE_PORT = {
    SOFTWARE: "i_irq_software",
    TIMER: "i_irq_timer",
    EXTERNAL: "i_irq_external",
}


def csrrsi(rd, csr, imm):
    """Monta csrrsi."""
    return (csr << 20) | (imm << 15) | (6 << 12) | (rd << 7) | 0x73


def csrrci(rd, csr, imm):
    """Monta csrrci."""
    return (csr << 20) | (imm << 15) | (7 << 12) | (rd << 7) | 0x73


def mul(rd, rs1, rs2):
    """Monta mul."""
    return _r(rd, 0, rs1, rs2, 1)


def div(rd, rs1, rs2):
    """Monta div."""
    return _r(rd, 4, rs1, rs2, 1)


def add(rd, rs1, rs2):
    """Monta add."""
    return _r(rd, 0, rs1, rs2, 0)


def sub(rd, rs1, rs2):
    """Monta sub."""
    return _r(rd, 0, rs1, rs2, 0x20)


def or_(rd, rs1, rs2):
    """Monta or."""
    return _r(rd, 6, rs1, rs2, 0)


def lw(rd, rs1, imm):
    """Monta lw."""
    return _i(0x03, rd, 2, rs1, imm)


def jal(rd, imm):
    """Monta jal."""
    return (
        (((imm >> 20) & 1) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | (rd << 7)
        | 0x6F
    )


def jalr(rd, rs1, imm):
    """Monta jalr."""
    return _i(0x67, rd, 0, rs1, imm)


def load_immediate(rd, value):
    """Devolve as palavras que carregam um valor de 32 bits em rd."""
    high = ((value + 0x800) >> 12) & 0xFFFFF
    low = value - (((value + 0x800) >> 12) << 12)
    return [lui(rd, high), addi(rd, rd, low)]


class Program:
    """Programa de linha reta com a soma esperada de cada endereço."""

    def __init__(self, base):
        """Começa vazio; base é o endereço da primeira palavra."""
        self.base = base
        self.words = []
        self.expected = {}
        self.kinds = {}
        self.count = 0
        self.masked = set()
        self.final = 0

    @property
    def pc(self):
        """Endereço da próxima palavra."""
        return self.base + 4 * len(self.words)

    def emit(self, word, kind="plain", inc=0):
        """Anexa uma palavra executada, com o tipo e a soma dela."""
        self.expected[self.pc] = self.count
        self.kinds[self.pc] = kind
        self.words.append(word)
        self.count += inc

    def skipped(self, word):
        """Anexa uma palavra que um desvio pula e nunca executa."""
        self.words.append(word)


def emit_inc(prog):
    """Soma simples."""
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_mul(prog):
    """Multiplicação que vale 1, somada em seguida."""
    prog.emit(mul(13, 14, 15), "mul")
    prog.emit(add(10, 10, 13), "inc", 1)


def emit_div(prog):
    """Divisão que vale 1, somada em seguida."""
    prog.emit(div(13, 14, 15), "div")
    prog.emit(add(10, 10, 13), "inc", 1)


def emit_misaligned(prog):
    """Store e load desalinhados do mesmo valor; erro vai a x25."""
    prog.emit(sw(10, 19, 1), "mis")
    prog.emit(lw(13, 19, 1), "mis")
    prog.emit(sub(13, 13, 10), "mis")
    prog.emit(or_(25, 25, 13), "mis")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_memory(prog):
    """Contador em memória: lê, soma e escreve."""
    prog.emit(lw(13, 20, 0), "mem")
    prog.emit(addi(13, 13, 1), "mem")
    prog.emit(sw(13, 20, 0), "mem")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_csr(prog):
    """Contador em mscratch: lê, soma e escreve."""
    prog.emit(csrrs(13, MSCRATCH, 0), "csr")
    prog.emit(addi(13, 13, 1), "csr")
    prog.emit(csrrw(0, MSCRATCH, 13), "csr")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_branch(prog):
    """Desvio tomado que pula uma soma de mil."""
    prog.emit(_b(0, 0, 0, 8), "br")
    prog.skipped(addi(10, 10, 1000))
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_jumps(prog):
    """JAL seguido de JALR que pula uma soma de mil."""
    prog.emit(jal(1, 4), "jal")
    prog.emit(jalr(0, 1, 8), "jalr")
    prog.skipped(addi(10, 10, 1000))
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_ecall(prog):
    """ECALL, que o tratador de exceção pula."""
    prog.emit(ECALL, "ecall")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_ebreak(prog):
    """EBREAK, que o tratador de exceção pula."""
    prog.emit(EBREAK, "ecall")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_illegal(prog):
    """Instrução ilegal, que o tratador de exceção pula."""
    prog.emit(ILLEGAL_WORD, "ill")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_wfi(prog):
    """WFI, que o núcleo executa como NOP."""
    prog.emit(WFI, "wfi")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_fencei(prog):
    """FENCE.I, que redireciona o pipeline para a instrução seguinte."""
    prog.emit(FENCE_I, "fencei")
    prog.emit(addi(10, 10, 1), "inc", 1)


def emit_masked(prog):
    """Janela com mstatus.MIE em zero: nada é tomado dentro dela."""
    prog.emit(csrrci(0, MSTATUS, MIE_BIT), "mstatus")
    for _ in range(6):
        prog.masked.add(prog.pc)
        emit_inc(prog)
    prog.masked.add(prog.pc)
    prog.emit(csrrsi(0, MSTATUS, MIE_BIT), "mstatus")
    prog.emit(addi(10, 10, 1), "inc", 1)


BASE_GROUPS = (
    emit_inc,
    emit_mul,
    emit_div,
    emit_misaligned,
    emit_memory,
    emit_csr,
    emit_branch,
    emit_jumps,
    emit_ecall,
    emit_ebreak,
    emit_illegal,
    emit_wfi,
    emit_masked,
)


def handler_words():
    """Palavras do tratador direto, que também serve a cada entrada.

    Interrupção (bit 31 de mcause em 1) registra mcause, mepc e x10 e
    reconhece a linha com um store em ACK_BASE + 4 x causa. Exceção soma
    4 a mepc e conta em x26.
    """
    return [
        csrrs(29, MCAUSE, 0),
        _b(5, 29, 0, 44),
        csrrs(30, MEPC, 0),
        sw(29, 28, 0),
        sw(30, 28, 4),
        sw(10, 28, 8),
        addi(28, 28, 12),
        _i(0x13, 29, 7, 29, 15),
        _i(0x13, 29, 1, 29, 2),
        add(29, 29, 27),
        sw(0, 29, 0),
        MRET,
        csrrs(30, MEPC, 0),
        addi(30, 30, 4),
        csrrw(0, MEPC, 30),
        addi(26, 26, 1),
        MRET,
    ]


def header_words(base, mtvec, enable, mie_on, sdram):
    """Prepara registradores, mtvec, mie e (se pedido) mstatus.MIE."""
    data = SDRAM_BASE if sdram else RAM_BASE
    words = [NOP]
    words += load_immediate(5, mtvec)
    words.append(csrrw(0, MTVEC, 5))
    words += load_immediate(7, RAM_BASE)
    words += load_immediate(27, ACK_BASE)
    words += load_immediate(28, LOG_BASE)
    words += load_immediate(19, data + DATA_MISALIGNED)
    words += load_immediate(20, data + DATA_COUNTER)
    words += [addi(14, 0, 1), addi(15, 0, 1)]
    words += load_immediate(5, enable)
    words.append(csrrs(0, MIE, 5))
    if mie_on:
        words.append(csrrsi(0, MSTATUS, MIE_BIT))
    check_true(base >= 0)
    return words


def group_choices(options):
    """Tipos de grupo que o sorteio pode escolher nestas opções."""
    groups = BASE_GROUPS
    if options.get("no_masked_window"):
        groups = tuple(g for g in groups if g is not emit_masked)
    return groups + tuple(options.get("extra", ()))


def emit_tail(prog):
    """Guarda os resultados na RAM e sinaliza o fim do programa."""
    prog.emit(addi(14, 0, 1))
    prog.emit(lw(13, 20, 0))
    prog.emit(csrrs(5, MSCRATCH, 0))
    for index, reg in enumerate((10, 26, 25, 13, 5, 28)):
        offset = RESULT_BASE - RAM_BASE + 4 * index
        prog.emit(sw(reg, 7, offset))
    prog.emit(sw(14, 7, DONE_ADDR - RAM_BASE))
    prog.emit(jal_self())


def build_sweep(base, seed, groups=110, **options):
    """Monta o programa sorteado; devolve (imagem, Program).

    As opções são ``enable`` (bits de mie), ``mie_on``, ``sdram``,
    ``extra`` (grupos a mais), ``no_masked_window`` e ``boot_jump``.
    """
    prog = Program(base)
    head = header_words(
        base,
        base + HANDLER_OFFSET,
        options.get("enable", TIMER),
        options.get("mie_on", True),
        options.get("sdram"),
    )
    for word in head:
        prog.emit(word)
    rng = Prng(seed)
    choices = group_choices(options)
    for _ in range(groups):
        choices[rng.getrandbits(8) % len(choices)](prog)
    prog.final = prog.count
    emit_tail(prog)
    check_true(len(prog.words) * 4 < HANDLER_OFFSET)
    prog.words += [NOP] * (HANDLER_OFFSET // 4 - len(prog.words))
    prog.words += handler_words()
    imem = {base + 4 * i: w for i, w in enumerate(prog.words)}
    if options.get("boot_jump"):
        boot = [NOP, *load_immediate(1, base), jalr(0, 1, 0)]
        imem.update({4 * i: w for i, w in enumerate(boot)})
    return imem, prog


class Lines:
    """Linhas de interrupção, mantidas em nível até o reconhecimento.

    ``held`` lista as linhas que sobem juntas e só caem quando o store
    do tratador as reconhece; ``masked`` lista linhas que ficam sempre
    em 1 (para provar que a máscara as barra). Quando todas as linhas
    de ``held`` caem, a próxima subida espera duas instruções do
    programa principal retiradas (para haver progresso, pois uma linha
    que sobe antes disso refaz a mesma entrada sem fim) e o próximo
    intervalo de ``gaps``, em ciclos.
    """

    def __init__(self, held, gaps, masked=(), main=(0, HANDLER_OFFSET)):
        """Guarda as linhas, os intervalos, as fixas e a faixa."""
        self.held = tuple(held)
        self.gaps = tuple(gaps)
        self.masked = tuple(masked)
        self.main = main
        self.cycle = 0
        self.raised_at = {}
        self.state = "gap"
        self.progress = 0
        self.waiting_until = self.gaps[0]
        self.round = 0
        self.raises = 0

    def _acknowledged(self, dut, line):
        """Diz se o store de reconhecimento desta linha ocorreu."""
        if not (int(dut.o_ram_en.value) and int(dut.o_ram_wren.value)):
            return False
        return (int(dut.o_ram_addr.value) & ~3) == LINE_ADDRESS[line]

    def _retired_main(self, dut):
        """Diz se uma instrução do programa principal foi retirada."""
        pc = int(dut.o_if_addr.value)
        return bool(int(dut.o_retire.value)) and (
            self.main[0] <= pc < self.main[1]
        )

    def _schedule(self, retired_main):
        """Faz a máquina de subida andar um ciclo."""
        if self.raised_at:
            return
        if self.state == "active":
            self.state = "progress"
            self.progress = 0
        if self.state == "progress":
            self.progress += int(retired_main)
            if self.progress >= PROGRESS_RETIRES:
                self.round += 1
                gap = self.gaps[self.round % len(self.gaps)]
                self.waiting_until = self.cycle + gap
                self.state = "gap"
        elif self.cycle >= self.waiting_until:
            self.raised_at = dict.fromkeys(self.held, self.cycle)
            self.raises += 1
            self.state = "active"

    def __call__(self, dut):
        """Avança um ciclo: reconhece, sobe e escreve as portas."""
        self.cycle += 1
        for line in self.held:
            if line in self.raised_at and self._acknowledged(dut, line):
                del self.raised_at[line]
        self._schedule(self._retired_main(dut))
        for line, port in LINE_PORT.items():
            high = line in self.raised_at or line in self.masked
            getattr(dut, port).value = int(high)


def check_count(entries, minimum):
    """Confere que houve ao menos `minimum` interrupções."""
    check_true(len(entries) >= minimum, f"só {len(entries)} interrupções")


def read_log(ram):
    """Lê as entradas (mcause, mepc, x10) que o tratador registrou."""
    entries = []
    address = LOG_BASE
    while address in ram:
        entries.append((ram[address], ram[address + 4], ram[address + 8]))
        address += 12
    return entries


def check_sweep(ram, prog, entries, fault_kinds=("ecall", "ill")):
    """Confere a soma, a precisão de mepc e os efeitos únicos."""
    result = [ram.get(RESULT_BASE + 4 * i) for i in range(RESULT_COUNT)]
    faults = sum(1 for kind in prog.kinds.values() if kind in fault_kinds)
    check_equal(result[0], prog.final, "soma final de x10")
    check_equal(result[1], faults, "exceções síncronas tratadas")
    check_equal(result[2], 0, "acesso desalinhado corrompido")
    memory = list(prog.kinds.values()).count("mem")
    check_equal(result[3], memory // 3, "contador em memória")
    scratch = list(prog.kinds.values()).count("csr")
    check_equal(result[4], scratch // 3, "contador em mscratch")
    for cause, epc, snapshot in entries:
        check_true(epc in prog.expected, f"mepc {epc:#x} fora do programa")
        check_equal(snapshot, prog.expected[epc], f"x10 em mepc {epc:#x}")
        check_true(epc not in prog.masked, f"tomada na janela {epc:#x}")
        check_true(cause & 0x80000000, f"causa {cause:#x} sem bit 31")


def covered_kinds(prog, entries):
    """Tipos de instrução que uma interrupção interrompeu."""
    return {prog.kinds[epc] for _, epc, _ in entries}


async def run_sweep(dut, base, seed, gaps, **options):
    """Roda um programa sorteado e devolve (RAM, Program, registro)."""
    imem, prog = build_sweep(base, seed, **options)
    lines = Lines(
        held=options.get("held", (TIMER,)),
        gaps=gaps,
        masked=options.get("masked", (SOFTWARE, EXTERNAL)),
        main=(base, base + HANDLER_OFFSET),
    )
    run_options = {
        "imem": imem,
        "monitor": lines,
        "max_cycles": options.get("max_cycles", 12000),
    }
    for name in ("sdram_stall", "ic_latency"):
        if name in options:
            run_options[name] = options[name]
    if options.get("sdram"):
        run_options["sdram"] = {}
    ram = await run_program(dut, [], **run_options)
    entries = read_log(ram)
    check_equal(ram[RESULT_BASE + 20], LOG_BASE + 12 * len(entries))
    return ram, prog, entries
