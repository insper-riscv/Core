"""Testes de fencei_unit com cache de dados.

O FENCE.I fica retido em EX por um ciclo (para os stores chegarem à
cache), pede o flush por um ciclo e só conclui com a confirmação da
cache, no ciclo do pedido ou em qualquer ciclo depois dele.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zifencei.fencei_unit import (
    FUNCT3_FENCE_I,
    OPCODE_MISC_MEM,
    cycle,
    start,
)

FENCE_I = (OPCODE_MISC_MEM, FUNCT3_FENCE_I)
FENCE = (OPCODE_MISC_MEM, 0)


@cocotb.test()
async def test_ack_in_pulse_cycle(dut):
    """Confirmação no ciclo do pulso: retém, pede flush e conclui."""
    await start(dut)
    check_equal(await cycle(dut, 1, 1, FENCE_I), (0, 1, 0), "chegada")
    check_equal(await cycle(dut, 1, 1, FENCE_I, 1), (1, 0, 1), "pulso")
    check_equal(await cycle(dut, 0, 1, FENCE_I), (0, 0, 0), "ocioso")


@cocotb.test()
async def test_late_ack(dut):
    """Confirmação tardia: segue retido até a cache confirmar."""
    await start(dut)
    check_equal(await cycle(dut, 1, 1, FENCE_I), (0, 1, 0), "chegada")
    check_equal(await cycle(dut, 1, 1, FENCE_I), (1, 1, 0), "pulso")
    for index in range(3):
        seen = await cycle(dut, 1, 1, FENCE_I)
        check_equal(seen, (0, 1, 0), f"espera {index}")
    check_equal(await cycle(dut, 1, 1, FENCE_I, 1), (0, 0, 1), "confirmação")
    check_equal(await cycle(dut, 0, 1, FENCE_I), (0, 0, 0), "ocioso")


@cocotb.test()
async def test_pipeline_stalled_while_armed(dut):
    """Com o pipeline parado o pulso espera, e EX segue retido."""
    await start(dut)
    check_equal(await cycle(dut, 1, 1, FENCE_I), (0, 1, 0), "chegada")
    for index in range(2):
        seen = await cycle(dut, 1, 0, FENCE_I)
        check_equal(seen, (0, 1, 0), f"parado {index}")
    check_equal(await cycle(dut, 1, 1, FENCE_I, 1), (1, 0, 1), "pulso")


@cocotb.test()
async def test_plain_fence_is_nop(dut):
    """O FENCE comum e as bolhas não retêm nem pedem flush."""
    await start(dut)
    check_equal(await cycle(dut, 1, 1, FENCE), (0, 0, 0), "FENCE")
    check_equal(await cycle(dut, 0, 1, FENCE_I), (0, 0, 0), "bolha")
