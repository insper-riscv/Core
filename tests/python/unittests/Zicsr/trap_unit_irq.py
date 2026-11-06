"""Testes do modulo.

trap_unit com uma interrupção a tomar: ela vence qualquer exceção
síncrona e o MRET da instrução em EX, grava a própria causa com mtval
zero, só vale com instrução válida e pipeline andando, e não aborta
FENCE.I, que redireciona o pipeline para a instrução seguinte.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.trap_unit import (
    CAUSE_BREAKPOINT,
    CAUSE_ECALL,
    CAUSE_ILLEGAL,
    OP_ALU,
    OP_LOAD,
    OP_STORE,
    probe,
    system,
)

CAUSES = (0x80000003, 0x80000007, 0x8000000B)
OP_MISC_MEM, FUNCT3_FENCE_I = 0b0001111, 0b001


async def irq(dut, cause, call, *args, **kw):
    """Chama a sonda com interrupção a tomar; devolve (saída, o_irq)."""
    dut.i_irq_take.value = 1
    dut.i_irq_cause.value = cause
    got = await call(dut, *args, **kw)
    return got, int(dut.o_irq.value)


async def idle(dut):
    """Desliga a interrupção a tomar."""
    dut.i_irq_take.value = 0
    dut.i_irq_cause.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_irq_on_a_plain_instruction(dut):
    """Verifica a tomada sobre uma instrução comum, com a causa dada."""
    for cause in CAUSES:
        got, flag = await irq(dut, cause, probe, OP_ALU)
        check_equal((got, flag), ((1, 0, cause, 0), 1))
    await idle(dut)
    got = await probe(dut, OP_ALU)
    check_equal((got[:2], int(dut.o_irq.value)), ((0, 0), 0))


@cocotb.test()
async def test_irq_wins_over_every_synchronous_exception(dut):
    """Verifica a interrupção sobre ecall, ebreak, ilegal e acessos."""
    cause = CAUSES[1]
    cases = (
        (system, (0x000,), {}),
        (system, (0x001,), {}),
        (system, (0x102,), {}),
        (probe, (OP_ALU,), {"illegal": 1}),
        (probe, (OP_LOAD, 0b010), {"ea": 1}),
        (probe, (OP_STORE, 0b001), {"ea": 1}),
        (probe, (OP_ALU,), {"cf_taken": 1, "cf_target": 2}),
    )
    for call, args, kw in cases:
        got, flag = await irq(dut, cause, call, *args, **kw)
        check_equal((got, flag), ((1, 0, cause, 0), 1), (args, kw))


@cocotb.test()
async def test_irq_aborts_mret(dut):
    """Verifica que o MRET em EX não retorna quando há interrupção."""
    got, flag = await irq(dut, CAUSES[2], system, 0x302)
    check_equal((got, flag), ((1, 0, CAUSES[2], 0), 1))
    await idle(dut)
    got = await system(dut, 0x302)
    check_equal((got[:2], int(dut.o_irq.value)), ((0, 1), 0))


@cocotb.test()
async def test_irq_needs_a_valid_instruction_and_a_running_pipeline(dut):
    """Verifica que sem instrução válida ou sem avanço nada é tomado."""
    for kw in ({"valid": 0}, {"run": 0}):
        got, flag = await irq(dut, CAUSES[1], probe, OP_ALU, **kw)
        check_equal((got[:2], flag), ((0, 0), 0), kw)


@cocotb.test()
async def test_irq_does_not_abort_fence_i(dut):
    """Verifica que FENCE.I espera um ciclo e não é abortado."""
    got, flag = await irq(dut, CAUSES[1], probe, OP_MISC_MEM, FUNCT3_FENCE_I)
    check_equal((got[:2], flag), ((0, 0), 0))
    got, flag = await irq(dut, CAUSES[1], probe, OP_MISC_MEM, 0)
    check_equal((got[0], flag), (1, 1))


@cocotb.test()
async def test_synchronous_exceptions_are_unchanged_without_irq(dut):
    """Verifica as causas síncronas intactas sem interrupção."""
    await idle(dut)
    check_equal(await system(dut, 0x000), (1, 0, CAUSE_ECALL, 0))
    check_equal(await system(dut, 0x001), (1, 0, CAUSE_BREAKPOINT, 0))
    check_equal(await system(dut, 0x102), (1, 0, CAUSE_ILLEGAL, 0))
