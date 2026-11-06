"""Testes de reg_id_ex: captura, stall, flush e reset do ID/EX."""

import cocotb

from tests.python.unittests.common.stage_register import (
    StageRegister,
    check_stage_register,
)

FIELDS = {
    "valid": 1,
    "pc": 32,
    "pc4": 32,
    "rs1": 5,
    "rd": 5,
    "rs1_val": 32,
    "rs2_val": 32,
    "imm": 32,
    "sel_pc4_alu": 1,
    "wb_sel": 1,
    "we_reg": 1,
    "ext_ram_op": 3,
    "sel_rs2_imm": 1,
    "sel_pc_rs1": 1,
    "alu_op": 5,
    "alu_sel": 8,
    "fwd_match_rs1": 3,
    "fwd_match_rs2": 3,
    "is_muldiv": 1,
    "is_csr": 1,
    "illegal": 1,
    "we_ram": 1,
    "re_ram": 1,
    "en_ram": 1,
    "opcode": 7,
    "funct3": 3,
}


@cocotb.test()
async def test_stage_register(dut):
    """Verifica o contrato do registrador ID/EX."""
    await check_stage_register(StageRegister(dut, FIELDS))
