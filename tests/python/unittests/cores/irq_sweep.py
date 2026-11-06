"""Testes do modulo.

Interrupção de timer tomada em instantes variados de um programa de
linha reta (soma, multiplicação, divisão, acesso desalinhado, CSR,
desvios, ecall, ebreak, instrução ilegal e wfi): o mepc é sempre a
primeira instrução que não completou, nenhuma instrução é perdida ou
repetida, e a interrupção nunca é tomada com mstatus.MIE em zero.
"""

import cocotb

from tests.python.unittests.checks import Prng, check_equal, check_true
from tests.python.unittests.cores.irq_common import (
    CAUSE_TIMER,
    EXTERNAL,
    SDRAM_BASE,
    SOFTWARE,
    TIMER,
    check_count,
    check_sweep,
    covered_kinds,
    emit_ebreak,
    emit_ecall,
    emit_illegal,
    run_sweep,
)

GAPS = (7, 9, 13, 8, 21, 11, 6, 17, 10, 29, 7, 15)
GAPS_FAST = (0, 1, 2, 0, 3, 1, 0, 5)
SEEDS = (0x1D2C3B4A, 0x0BADF00D, 0x600DCAFE)
ALL_KINDS = {"inc", "mul", "div", "mis", "mem", "csr", "br"}
FAULTS = (emit_ecall, emit_ebreak, emit_illegal) * 4


def sdram_stall(count):
    """Espera pseudoaleatória (0 a 5 ciclos) do count-ésimo acesso."""
    return Prng(0xACE0 + count).getrandbits(8) % 6


def ic_latency(count):
    """Espera pseudoaleatória (0 a 4 ciclos) da count-ésima busca."""
    return Prng(0xFE7C + count).getrandbits(8) % 5


def check_run(ram, prog, entries):
    """Confere a soma e a causa de cada entrada do programa."""
    check_sweep(ram, prog, entries)
    for cause, _, _ in entries:
        check_equal(cause, CAUSE_TIMER)


@cocotb.test()
async def test_timer_at_many_instants(dut):
    """Verifica mepc preciso com a interrupção em muitos instantes."""
    ram, prog, entries = await run_sweep(dut, 0, SEEDS[0], GAPS)
    check_run(ram, prog, entries)
    check_count(entries, 31)
    kinds = covered_kinds(prog, entries)
    check_true(kinds >= ALL_KINDS, f"tipos não cobertos: {ALL_KINDS - kinds}")


@cocotb.test()
async def test_timer_over_synchronous_exceptions(dut):
    """Verifica a interrupção sobre ecall, ebreak e instrução ilegal.

    A interrupção tem prioridade: a instrução que ia gerar a exceção
    fica como a de retorno e a exceção ocorre depois, uma vez só.
    """
    ram, prog, entries = await run_sweep(
        dut, 0, SEEDS[1], GAPS_FAST, extra=FAULTS
    )
    check_run(ram, prog, entries)
    kinds = covered_kinds(prog, entries)
    check_true(kinds >= {"ecall", "ill"}, f"tipos não cobertos: {kinds}")


@cocotb.test()
async def test_timer_back_to_back(dut):
    """Verifica interrupções com intervalos mínimos entre elas."""
    ram, prog, entries = await run_sweep(dut, 0, SEEDS[1], GAPS_FAST)
    check_run(ram, prog, entries)
    check_count(entries, 51)


@cocotb.test()
async def test_timer_with_sdram_data(dut):
    """Verifica a interrupção com dados na SDRAM e paradas variáveis."""
    ram, prog, entries = await run_sweep(
        dut, 0, SEEDS[2], GAPS, sdram=True, sdram_stall=sdram_stall
    )
    check_run(ram, prog, entries)
    check_count(entries, 21)


@cocotb.test()
async def test_timer_with_fetch_wait(dut):
    """Verifica a interrupção com código na SDRAM e esperas."""
    ram, prog, entries = await run_sweep(
        dut,
        SDRAM_BASE,
        SEEDS[0],
        GAPS,
        ic_latency=ic_latency,
        max_cycles=20000,
        boot_jump=True,
    )
    check_run(ram, prog, entries)
    check_count(entries, 21)


@cocotb.test()
async def test_masked_by_mie_bit(dut):
    """Verifica que o bit de mie em zero barra a linha de timer."""
    ram, prog, entries = await run_sweep(
        dut, 0, SEEDS[1], GAPS, enable=SOFTWARE | EXTERNAL, masked=()
    )
    check_sweep(ram, prog, entries)
    check_equal(entries, [], "interrupção tomada com MTIE em zero")


@cocotb.test()
async def test_masked_by_mstatus_mie(dut):
    """Verifica que mstatus.MIE em zero barra todas as interrupções."""
    ram, prog, entries = await run_sweep(
        dut,
        0,
        SEEDS[1],
        GAPS,
        enable=SOFTWARE | TIMER | EXTERNAL,
        mie_on=False,
        masked=(SOFTWARE, EXTERNAL),
        no_masked_window=True,
    )
    check_sweep(ram, prog, entries)
    check_equal(entries, [], "interrupção tomada com MIE em zero")
