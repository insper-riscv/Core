"""The base control_unit does not know the M extension: an M instruction is a NOP.

The M extension claims it in M/m_decode (tested in m_decode.py); without it (the
rv32i profile) the instruction passes with no effect.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.common.control_unit import build_instruction

OP_R = 0b0110011
CONTROL_OUTPUTS = (
    "o_sel_pc4_alu",
    "o_ext_imm_op",
    "o_wb_sel",
    "o_we_reg",
    "o_ext_ram_op",
    "o_sel_rs2_imm",
    "o_sel_pc_rs1",
    "o_alu_op",
    "o_we_ram",
    "o_re_ram",
    "o_en_ram",
)


@cocotb.test()
async def test_m_instructions_are_nops(dut):
    """Every funct3 of funct7 = 0000001 leaves all control outputs at zero."""
    for funct3 in range(8):
        dut.i_inst.value = build_instruction(OP_R, funct3, 0b0000001)
        await Timer(1, unit="ns")
        for name in CONTROL_OUTPUTS:
            got = int(getattr(dut, name).value)
            assert got == 0, f"M funct3={funct3}: {name}={got}, expected NOP (0)"


@cocotb.test()
async def test_base_r_type_still_decodes(dut):
    """add and sub (funct7 = 0000000 / 0100000) still write a register."""
    for funct7 in (0b0000000, 0b0100000):
        dut.i_inst.value = build_instruction(OP_R, 0b000, funct7)
        await Timer(1, unit="ns")
        assert int(dut.o_we_reg.value) == 1
