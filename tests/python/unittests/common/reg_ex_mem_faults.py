"""Testes de reg_ex_mem com HAS_ACCESS_FAULTS.

A validade do endereço para escrita no mapa do núcleo é registrada junto
com a classificação.

Mapa do teste: BOOT_MEMORY em [0, 4 KiB), FLASH em [4 KiB, 6 KiB),
RAM em [8 KiB, 16 KiB) e todo o resto pela porta externa. A
BOOT_MEMORY e a FLASH são só de leitura e recusam a escrita; a RAM e
tudo o que sai pela porta externa (o buraco entre as duas memórias e o
espaço acima da RAM) aceitam a escrita, e a porta externa responde erro
se nada atende o endereço. A leitura nunca é recusada pelo núcleo.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

CASES = [
    (0x00000000, 0),
    (0x00000FFC, 0),
    (0x00001000, 0),
    (0x000017FC, 0),
    (0x00001800, 1),
    (0x00001FFC, 1),
    (0x00002000, 1),
    (0x00003FFC, 1),
    (0x00004000, 1),
    (0x40000000, 1),
    (0x7FFFFFFC, 1),
    (0x80000000, 1),
    (0xF0000000, 1),
]


async def check_cases(dut, cases):
    """Confere a escrita aceita por endereço e a bolha."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 0
    dut.i_en.value = 1
    dut.i_flush.value = 0
    await RisingEdge(dut.i_clk)
    for address, wr in cases:
        dut.i_ea.value = address
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        check_equal(int(dut.o_ok_wr.value), wr, f"{address:#x}")
    dut.i_flush.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_equal(
        int(dut.o_ok_wr.value),
        1,
        "a bolha não pode gerar falha",
    )


@cocotb.test()
async def test_validity_of_each_region(dut):
    """Verifica a escrita aceita por região no EX/MEM."""
    await check_cases(dut, CASES)
