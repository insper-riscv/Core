"""Testes de reg_mem_wb: contrato do MEM/WB e as saídas derivadas."""

import cocotb

from tests.python.unittests.common.stage_register import (
    StageRegister,
    check_stage_register,
    start,
)

FIELDS = {
    "valid": 1,
    "alu_out": 32,
    "rd": 5,
    "we_reg": 1,
    "ext_ram_op": 3,
    "wb_sel": 1,
}

# Limites do mapa de endereços (generics padrão), em bytes.
ROM_END = 32 * 1024
EXT_BASE = 1048576 * 1024
EXT_RAM_LW, EXT_RAM_LH, EXT_RAM_LHU = 0, 1, 2
LAST_BYTE = 3


def is_cross(op, address):
    """Diz se o load cruza a palavra (LW desalinhado, LH no byte 3)."""
    offset = address & 3
    return (op == EXT_RAM_LW and offset != 0) or (
        op in (EXT_RAM_LH, EXT_RAM_LHU) and offset == LAST_BYTE
    )


def derived(values):
    """Devolve we_ok, a região e o cruzamento do endereço."""
    address = values["alu_out"]
    return {
        "we_ok": values["we_reg"] & values["valid"],
        "is_flash": int(address < ROM_END),
        "is_sdram": int(address >= EXT_BASE),
        "is_cross": int(is_cross(values["ext_ram_op"], address)),
    }


@cocotb.test()
async def test_stage_register(dut):
    """Verifica o contrato do registrador MEM/WB."""
    await check_stage_register(StageRegister(dut, FIELDS, derived))


@cocotb.test()
async def test_regions(dut):
    """Varre as fronteiras das regiões, os loads e os deslocamentos."""
    reg = StageRegister(dut, FIELDS, derived)
    await start(reg)
    for base in (0, ROM_END - 4, ROM_END, EXT_BASE - 4, EXT_BASE):
        for op in range(5):
            for offset in range(4):
                values = reg.random_inputs()
                values["alu_out"] = base + offset
                values["ext_ram_op"] = op
                await reg.step(values, (1, 0, 0))
                reg.expect(values, f"{base + offset:#x} op {op}")
