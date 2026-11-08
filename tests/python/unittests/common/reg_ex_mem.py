"""Testes de reg_ex_mem: contrato do EX/MEM e o we_ok derivado."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.common.stage_register import (
    StageRegister,
    check_stage_register,
)

FIELDS = {
    "valid": 1,
    "pc": 32,
    "funct3": 3,
    "alu_out": 32,
    "store_data": 32,
    "byte_mask": 4,
    "rd": 5,
    "we_reg": 1,
    "we_ram": 1,
    "re_ram": 1,
    "en_ram": 1,
    "ext_ram_op": 3,
    "wb_sel": 1,
}


def derived(values):
    """Devolve we_ok: a escrita de registrador só vale com validade."""
    return {"we_ok": values["we_reg"] & values["valid"]}


@cocotb.test()
async def test_stage_register(dut):
    """Verifica o contrato do registrador EX/MEM."""
    await check_stage_register(StageRegister(dut, FIELDS, derived))


async def classify(dut, address):
    """Registra um endereço efetivo e devolve (flash, sdram)."""
    dut.i_ea.value = address
    dut.i_en.value = 1
    dut.i_flush.value = 0
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return int(dut.o_is_flash.value), int(dut.o_is_sdram.value)


@cocotb.test()
async def test_address_class_is_registered(dut):
    """Verifica a classificação do endereço registrada em EX/MEM."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 0
    check_equal(await classify(dut, 0x00000010), (1, 0))
    check_equal(await classify(dut, 0x40000010), (0, 1))
    check_equal(await classify(dut, 0x00010000), (0, 0))
    dut.i_flush.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_equal((int(dut.o_is_flash.value), int(dut.o_is_sdram.value)), (0, 0))
