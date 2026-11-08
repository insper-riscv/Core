"""Testes do modulo.

Event counters on the core: a program counts its own taken branches and
load-use stalls.

The program selects an event in mhpmevent3 or mhpmevent4, runs a loop of
known length and reads the counter back, so the events of the core reach
the right counter with the right count.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import NOP
from tests.python.unittests.cores.misaligned_half import lw
from tests.python.unittests.cores.sdram_stall import (
    addi,
    beq,
    jal_self,
    lui,
    sw,
)

MIN_DIV_STALL = 32

MHPMEVENT3, MHPMEVENT4 = 0x323, 0x324
MHPMCOUNTER3, MHPMCOUNTER4 = 0xB03, 0xB04
HPMCOUNTER3 = 0xC03
MCOUNTINHIBIT = 0x320


def csr(funct3, rd, rs1, addr):
    """Executa csr."""
    return (addr << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x73


def csrrw(rd, addr, rs1):
    """Executa csrrw."""
    return csr(0b001, rd, rs1, addr)


def csrrs(rd, addr, rs1=0):
    """Executa csrrs."""
    return csr(0b010, rd, rs1, addr)


def bne(rs1, rs2, imm):
    """Executa bne."""
    return beq(rs1, rs2, imm) | (1 << 12)


def muldiv(funct3, rd, rs1, rs2):
    """Executa muldiv."""
    return (
        (1 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | 0x33
    )


DIV, REM = 0b100, 0b110


def program(event, iterations, body):
    """Executa program.

    Select `event` in mhpmevent3, run `body` `iterations` times and
    store the counter at RAM[0].
    """
    return [
        NOP,
        lui(7, RAM_BASE >> 12),
        addi(5, 0, event),
        csrrw(0, MHPMEVENT3, 5),
        addi(6, 0, iterations),
        *body,
        addi(6, 6, -1),
        bne(6, 0, -(4 * (len(body) + 1))),
        csrrs(8, MHPMCOUNTER3),
        sw(8, 7, 0),
        csrrs(9, HPMCOUNTER3),
        sw(9, 7, 4),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]


@cocotb.test()
async def test_taken_branches_are_counted(dut):
    """Verifica taken branches are counted."""
    ram = await run_program(dut, program(3, 10, [NOP]), max_cycles=3000)
    # the loop branch is taken nine times and falls through on the tenth
    check_equal(ram[RAM_BASE], 9)
    check_equal(ram[RAM_BASE + 4], 9, "the user mirror reads the same counter")


@cocotb.test()
async def test_load_use_stalls_are_counted(dut):
    """Verifica load use stalls are counted."""
    # a load and the use of its result
    body = [lw(10, 7, 8), addi(11, 10, 1)]
    ram = await run_program(dut, program(8, 6, body), max_cycles=3000)
    # the use waits two cycles for the load: one with the load in EX and
    # one with it in MEM
    check_equal(
        ram[RAM_BASE],
        12,
        f"two stall cycles per iteration, counted {ram[RAM_BASE]}",
    )


@cocotb.test()
async def test_event_zero_counts_nothing(dut):
    """Verifica event zero counts nothing."""
    ram = await run_program(dut, program(0, 10, [NOP]), max_cycles=3000)
    check_equal(ram[RAM_BASE], 0)


@cocotb.test()
async def test_mcountinhibit_holds_the_counter(dut):
    """Verifica mcountinhibit holds the counter."""
    prog = program(3, 10, [NOP])
    # inhibit the counter before the loop: bit 3 of mcountinhibit
    prog[4:4] = [addi(12, 0, 1 << 3), csrrw(0, MCOUNTINHIBIT, 12)]
    ram = await run_program(dut, prog, max_cycles=3000)
    check_equal(ram[RAM_BASE], 0)


@cocotb.test()
async def test_fused_pairs_are_counted(dut):
    """Verifica fused pairs are counted.

    Event 9 counts the REM that reuses the quotient and the remainder of
    the DIV before it.
    """
    prog = program(9, 3, [muldiv(DIV, 12, 10, 11), muldiv(REM, 13, 10, 11)])
    prog[4:4] = [addi(10, 0, 1000), addi(11, 0, 7)]
    ram = await run_program(dut, prog, max_cycles=6000)
    # the first DIV of the loop runs in full, the REM is fused; from the
    # second iteration on the record holds the DIV again (the fused REM
    # leaves it as it was), so every REM is fused
    check_equal(
        ram[RAM_BASE],
        3,
        f"one fused operation per iteration, counted {ram[RAM_BASE]}",
    )


@cocotb.test()
async def test_divider_stall_is_counted(dut):
    """Event 1 counts the cycles that a division holds the pipeline."""
    prog = program(1, 1, [muldiv(DIV, 12, 10, 11)])
    prog[4:4] = [addi(10, 0, 1000), addi(11, 0, 7)]
    ram = await run_program(dut, prog, max_cycles=3000)
    check_true(
        ram[RAM_BASE] >= MIN_DIV_STALL,
        f"a division stalls for more than {MIN_DIV_STALL} cycles, "
        f"counted {ram[RAM_BASE]}",
    )


MCYCLE, MSCRATCH = 0xB00, 0x340
READS = 16


def timing_program(addr):
    """Mede em ciclos READS leituras seguidas do CSR addr.

    Guarda a diferença de mcycle em RAM[0].
    """
    return [
        NOP,
        lui(7, RAM_BASE >> 12),
        csrrs(10, MCYCLE),
        *[csrrs(11, addr) for _ in range(READS)],
        csrrs(12, MCYCLE),
        *[NOP] * 3,
        sub(13, 12, 10),
        sw(13, 7, 0),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]


def sub(rd, rs1, rs2):
    """Executa sub."""
    return (0x20 << 25) | (rs2 << 20) | (rs1 << 15) | (rd << 7) | 0x33


def add(rd, rs1, rs2):
    """Executa add."""
    return (rs2 << 20) | (rs1 << 15) | (rd << 7) | 0x33


@cocotb.test()
async def test_a_bank_read_costs_one_cycle(dut):
    """Verifica que cada CSR do banco do Zihpm custa um ciclo a mais."""
    base = await run_program(dut, timing_program(MSCRATCH), max_cycles=3000)
    bank = await run_program(
        dut, timing_program(MHPMCOUNTER3), max_cycles=3000
    )
    check_equal(
        bank[RAM_BASE] - base[RAM_BASE],
        READS,
        f"base {base[RAM_BASE]}, banco {bank[RAM_BASE]}",
    )


@cocotb.test()
async def test_a_read_right_after_a_write_sees_the_new_value(dut):
    """Verifica a escrita de um contador seguida da leitura e do uso."""
    prog = [
        NOP,
        lui(7, RAM_BASE >> 12),
        addi(5, 0, 0x55),
        csrrw(0, MHPMCOUNTER3, 5),
        csrrs(8, MHPMCOUNTER3),
        add(9, 8, 8),
        addi(5, 0, 0x0F),
        csrrs(10, MHPMCOUNTER3, 5),
        csrrs(11, MHPMCOUNTER3),
        sw(8, 7, 0),
        sw(9, 7, 4),
        sw(10, 7, 8),
        sw(11, 7, 12),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    ram = await run_program(dut, prog, max_cycles=3000)
    check_equal(ram[RAM_BASE], 0x55)
    check_equal(ram[RAM_BASE + 4], 0xAA)
    check_equal(ram[RAM_BASE + 8], 0x55, "csrrs devolve o valor antigo")
    check_equal(ram[RAM_BASE + 12], 0x5F, "e escreve o valor OU a mascara")


INSTRET = 0xC02
HIGH_BIT = 0x40000000
# Limite abaixo do qual o instret lido não carrega bits do contador.
INSTRET_LIMIT = 0x1000


@cocotb.test()
async def test_a_counter_read_does_not_leak_into_the_next_csr_read(dut):
    """Verifica que o valor lido do banco não vaza na leitura seguinte.

    A leitura registrada do banco guarda o valor do contador lido; o CSR
    lido logo depois (instret) nao pode receber esses bits.
    """
    prog = [
        NOP,
        lui(7, RAM_BASE >> 12),
        lui(5, HIGH_BIT >> 12),
        csrrw(0, MHPMCOUNTER3, 5),
        csrrs(8, MHPMCOUNTER3),
        csrrs(9, INSTRET),
        sw(8, 7, 0),
        sw(9, 7, 4),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    ram = await run_program(dut, prog, max_cycles=3000)
    check_equal(ram[RAM_BASE], HIGH_BIT, "o contador devolve o valor escrito")
    check_true(
        ram[RAM_BASE + 4] < INSTRET_LIMIT,
        f"instret sem os bits do contador, leu {ram[RAM_BASE + 4]:#x}",
    )
