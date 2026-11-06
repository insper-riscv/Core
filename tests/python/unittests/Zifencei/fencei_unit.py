"""Testes de fencei_unit sem cache de dados.

Sem cache de dados o FENCE.I conclui no ciclo em que chega a EX com o
pipeline avançando, sem reter o estágio nem pedir flush.
"""

import itertools

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

OPCODE_MISC_MEM = 0b0001111
OPCODE_LOAD = 0b0000011
OPCODE_OP = 0b0110011
FUNCT3_FENCE_I = 0b001


async def start(dut):
    """Liga o clock e aplica reset com a unidade ociosa."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_ex_valid.value = 0
    dut.i_run.value = 0
    dut.i_opcode.value = 0
    dut.i_funct3.value = 0
    dut.i_dc_done.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def cycle(dut, valid, run, instr, dc_done=0):
    """Aplica um ciclo e devolve (flush_req, busy, take) antes da borda.

    A instrução vem como (opcode, funct3).
    """
    dut.i_ex_valid.value = valid
    dut.i_run.value = run
    dut.i_opcode.value, dut.i_funct3.value = instr
    dut.i_dc_done.value = dc_done
    await Timer(1, unit="ns")
    seen = (
        int(dut.o_flush_req.value),
        int(dut.o_busy.value),
        int(dut.o_take.value),
    )
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return seen


@cocotb.test()
async def test_take_only_on_fencei(dut):
    """O pulso sai só com FENCE.I válido e pipeline avançando."""
    await start(dut)
    for valid, run, opcode, funct3 in itertools.product(
        (0, 1), (0, 1), (OPCODE_MISC_MEM, OPCODE_LOAD, OPCODE_OP), range(8)
    ):
        seen = await cycle(dut, valid, run, (opcode, funct3))
        is_fencei = (
            valid
            and run
            and opcode == OPCODE_MISC_MEM
            and funct3 == FUNCT3_FENCE_I
        )
        check_equal(seen, (0, 0, int(is_fencei)), (valid, run, opcode, funct3))
