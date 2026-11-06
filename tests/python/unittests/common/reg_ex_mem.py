"""Testes de reg_ex_mem: contrato do EX/MEM e o we_ok derivado."""

import cocotb

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
