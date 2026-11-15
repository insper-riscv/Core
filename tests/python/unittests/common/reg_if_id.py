"""Testes de reg_if_id: captura, stall, flush e reset do IF/ID."""

import cocotb

from tests.python.unittests.common.stage_register import (
    StageRegister,
    check_stage_register,
)

FIELDS = {"valid": 1, "pc": 32, "pc4": 32, "inst": 32}

# Só o opcode da instrução é limpo; PC, PC + 4 e o resto da palavra são dados.
KEEP = {"pc": 0xFFFFFFFF, "pc4": 0xFFFFFFFF, "inst": 0xFFFFFF80}


@cocotb.test()
async def test_stage_register(dut):
    """Verifica o contrato do registrador IF/ID."""
    await check_stage_register(StageRegister(dut, FIELDS, keep=KEEP))
