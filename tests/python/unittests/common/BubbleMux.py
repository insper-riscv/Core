"""Testes de BubbleMux."""

import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def test_passthrough(dut):
    """Verifica passthrough.

    i_sel='0': todos os sinais passam direto da entrada para a saida.
    """
    dut.i_sel.value = 0
    dut.i_we_reg.value = 1
    dut.i_we_ram.value = 1
    dut.i_re_ram.value = 1
    dut.i_en_ram.value = 1
    await Timer(1, units="ns")
    assert int(dut.o_we_reg.value) == 1
    assert int(dut.o_we_ram.value) == 1
    assert int(dut.o_re_ram.value) == 1
    assert int(dut.o_en_ram.value) == 1
    dut._log.info("test_passthrough: OK")


@cocotb.test()
async def test_bubble_zeros_all(dut):
    """Zera todos os sinais com i_sel='1'.

    Vale mesmo se as entradas estiverem em '1'.
    """
    dut.i_sel.value = 1
    dut.i_we_reg.value = 1
    dut.i_we_ram.value = 1
    dut.i_re_ram.value = 1
    dut.i_en_ram.value = 1
    await Timer(1, units="ns")
    assert int(dut.o_we_reg.value) == 0
    assert int(dut.o_we_ram.value) == 0
    assert int(dut.o_re_ram.value) == 0
    assert int(dut.o_en_ram.value) == 0
    dut._log.info("test_bubble_zeros_all: OK")


@cocotb.test()
async def test_toggle_sel(dut):
    """Verifica toggle sel.

    Alterna i_sel com entradas constantes em 1: deve seguir o i_sel.
    """
    dut.i_we_reg.value = 1
    dut.i_we_ram.value = 1
    dut.i_re_ram.value = 1
    dut.i_en_ram.value = 1
    for sel in [0, 1, 0, 1]:
        dut.i_sel.value = sel
        await Timer(1, units="ns")
        expected = 1 - sel
        assert int(dut.o_we_reg.value) == expected, f"sel={sel}"
    dut._log.info("test_toggle_sel: OK")
