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
    "fwd_rs1": 2,
    "fwd_rs2": 2,
    "is_muldiv": 1,
    "is_csr": 1,
    "illegal": 1,
    "we_ram": 1,
    "re_ram": 1,
    "en_ram": 1,
    "opcode": 7,
    "funct3": 3,
}

# Campos de dados, que flush e reset não limpam.
KEEP = dict.fromkeys(("pc", "pc4", "rs1_val", "rs2_val", "imm"), 0xFFFFFFFF)
KEEP |= {"fwd_rs1": 0xFF, "fwd_rs2": 0xFF}

# Cópias do seletor de adiantamento (FWD_COPIES de fwd_consts).
COPIES = 4


def replicate(code):
    """Repete o código do seletor em cada cópia (bits 2i+1:2i)."""
    return sum(code << (2 * copy) for copy in range(COPIES))


def derived(values):
    """Devolve os seletores de adiantamento replicados nas cópias."""
    return {
        "fwd_rs1": replicate(values["fwd_rs1"]),
        "fwd_rs2": replicate(values["fwd_rs2"]),
    }


@cocotb.test()
async def test_stage_register(dut):
    """Verifica o contrato do registrador ID/EX."""
    await check_stage_register(StageRegister(dut, FIELDS, derived, KEEP))
