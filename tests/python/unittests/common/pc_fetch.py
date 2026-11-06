"""Testes de pc_fetch: registrador de PC, PC + 4 e seleção da fonte."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng, check_equal

MASK32 = 0xFFFFFFFF
PC4, BRANCH, JALR, REDIRECT = 0, 1, 2, 3


async def start(dut):
    """Liga o clock e aplica reset, deixando o PC em zero."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_pc_we.value = 0
    dut.i_pc_src.value = PC4
    dut.i_branch_target.value = 0
    dut.i_jalr_target.value = 0
    dut.i_redirect_pc.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def step(dut, enable, source, targets):
    """Aplica uma borda e devolve (pc, pc4) depois dela.

    Os alvos vêm como (branch, jalr, redirect).
    """
    dut.i_pc_we.value = enable
    dut.i_pc_src.value = source
    dut.i_branch_target.value = targets[0]
    dut.i_jalr_target.value = targets[1]
    dut.i_redirect_pc.value = targets[2]
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return int(dut.o_pc.value), int(dut.o_pc4.value)


@cocotb.test()
async def test_reset_and_sequential(dut):
    """Depois do reset o PC é zero e avança de 4 em 4 com a escrita."""
    await start(dut)
    check_equal(int(dut.o_pc.value), 0, "PC no reset")
    check_equal(int(dut.o_pc4.value), 4, "PC + 4 no reset")
    for index in range(1, 6):
        pc, pc4 = await step(dut, 1, PC4, (0, 0, 0))
        check_equal((pc, pc4), (4 * index, 4 * index + 4), index)


@cocotb.test()
async def test_source_selection(dut):
    """Cada fonte carrega o seu alvo; PC + 4 acompanha o novo PC."""
    await start(dut)
    prng = Prng(0xFE7C)
    for index in range(32):
        targets = tuple(prng.getrandbits(32) for _ in range(3))
        for source in (BRANCH, JALR, REDIRECT):
            pc, pc4 = await step(dut, 1, source, targets)
            check_equal(pc, targets[source - 1], (index, source))
            check_equal(pc4, (pc + 4) & MASK32, (index, source))


@cocotb.test()
async def test_stall_and_redirect_priority(dut):
    """Sem escrita o PC congela; o redirecionamento ignora o stall."""
    await start(dut)
    pc, _ = await step(dut, 1, BRANCH, (0x1000, 0x2000, 0x3000))
    check_equal(pc, 0x1000, "alvo de desvio")
    for source in (PC4, BRANCH, JALR):
        held, _ = await step(dut, 0, source, (0x4000, 0x5000, 0x6000))
        check_equal(held, 0x1000, f"stall com fonte {source}")
    pc, _ = await step(dut, 0, REDIRECT, (0x4000, 0x5000, 0x6000))
    check_equal(pc, 0x6000, "redirecionamento em stall")
