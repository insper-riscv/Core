import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def test_passthrough(dut):
    """sel_bubble='0': todos os sinais passam direto da entrada para a saida."""
    dut.sel_bubble.value = 0
    dut.weReg_i.value    = 1
    dut.weRAM_i.value    = 1
    dut.reRAM_i.value    = 1
    dut.eRAM_i.value     = 1
    dut.startMul_i.value = 1
    await Timer(1, units="ns")
    assert int(dut.weReg_o.value)    == 1
    assert int(dut.weRAM_o.value)    == 1
    assert int(dut.reRAM_o.value)    == 1
    assert int(dut.eRAM_o.value)     == 1
    assert int(dut.startMul_o.value) == 1
    dut._log.info("test_passthrough: OK")


@cocotb.test()
async def test_bubble_zeros_all(dut):
    """sel_bubble='1': todos os sinais sao zerados, mesmo se as entradas
    estiverem em '1'."""
    dut.sel_bubble.value = 1
    dut.weReg_i.value    = 1
    dut.weRAM_i.value    = 1
    dut.reRAM_i.value    = 1
    dut.eRAM_i.value     = 1
    dut.startMul_i.value = 1
    await Timer(1, units="ns")
    assert int(dut.weReg_o.value)    == 0
    assert int(dut.weRAM_o.value)    == 0
    assert int(dut.reRAM_o.value)    == 0
    assert int(dut.eRAM_o.value)     == 0
    assert int(dut.startMul_o.value) == 0
    dut._log.info("test_bubble_zeros_all: OK")


@cocotb.test()
async def test_toggle_sel(dut):
    """Alterna sel_bubble com entradas constantes em 1: deve seguir o sel."""
    dut.weReg_i.value    = 1
    dut.weRAM_i.value    = 1
    dut.reRAM_i.value    = 1
    dut.eRAM_i.value     = 1
    dut.startMul_i.value = 1
    for sel in [0, 1, 0, 1]:
        dut.sel_bubble.value = sel
        await Timer(1, units="ns")
        expected = 1 - sel
        assert int(dut.weReg_o.value) == expected, f"sel={sel}"
    dut._log.info("test_toggle_sel: OK")
