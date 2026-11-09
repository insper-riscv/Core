"""Testes de reg_ex_mem com HAS_ACCESS_FAULTS.

A validade do endereço no mapa é registrada junto com a classificação.

Mapa do teste: ROM em [0, 4 KiB), RAM em [8 KiB, 16 KiB), janela externa
vazia, periféricos a partir de 0x80000000 nos slots 0 e 3 (bits 30:28 do
endereço). A ROM aceita leitura e não escrita, a RAM e os slots ocupados
aceitam as duas, e o resto (os buracos e os slots vazios) não aceita
nenhuma.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

CASES = [
    (0x00000000, 1, 0),
    (0x00000FFC, 1, 0),
    (0x00001000, 0, 0),
    (0x00001FFC, 0, 0),
    (0x00002000, 1, 1),
    (0x00003FFC, 1, 1),
    (0x00004000, 0, 0),
    (0x40000000, 0, 0),
    (0x7FFFFFFC, 0, 0),
    (0x80000000, 1, 1),
    (0x8FFFFFFC, 1, 1),
    (0x90000000, 0, 0),
    (0xA0000000, 0, 0),
    (0xB0000010, 1, 1),
    (0xC0000000, 0, 0),
    (0xF0000000, 0, 0),
]


async def check_cases(dut, cases):
    """Confere (leitura, escrita) aceitas por endereço e a bolha."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 0
    dut.i_en.value = 1
    dut.i_flush.value = 0
    await RisingEdge(dut.i_clk)
    for address, rd, wr in cases:
        dut.i_ea.value = address
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        got = (int(dut.o_ok_rd.value), int(dut.o_ok_wr.value))
        check_equal(got, (rd, wr), f"{address:#x}")
    dut.i_flush.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_equal(
        (int(dut.o_ok_rd.value), int(dut.o_ok_wr.value)),
        (1, 1),
        "a bolha não pode gerar falha",
    )


@cocotb.test()
async def test_validity_of_each_region(dut):
    """Verifica leitura e escrita aceitas por região no EX/MEM."""
    await check_cases(dut, CASES)
