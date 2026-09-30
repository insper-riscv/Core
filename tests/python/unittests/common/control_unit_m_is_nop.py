"""The base control_unit does not know the M extension: an M instruction is a NOP.

The M extension claims it in M/m_decode (tested in m_decode.py); without it (the
rv32i profile) the instruction passes with no effect.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.common.control_unit import build_instruction

OP_R = 0b0110011
CONTROL_OUTPUTS = (
    "selMuxPc4ALU",
    "opExImm",
    "selMuxALUPc4RAM",
    "weReg",
    "opExRAM",
    "selMuxRS2Imm",
    "selPCRS1",
    "opALU",
    "weRAM",
    "reRAM",
    "eRAM",
)


@cocotb.test()
async def test_m_instructions_are_nops(dut):
    """Every funct3 of funct7 = 0000001 leaves all control outputs at zero."""
    for funct3 in range(8):
        dut.instruction.value = build_instruction(OP_R, funct3, 0b0000001)
        await Timer(1, unit="ns")
        for name in CONTROL_OUTPUTS:
            got = int(getattr(dut, name).value)
            assert got == 0, f"M funct3={funct3}: {name}={got}, expected NOP (0)"


@cocotb.test()
async def test_base_r_type_still_decodes(dut):
    """add and sub (funct7 = 0000000 / 0100000) still write a register."""
    for funct7 in (0b0000000, 0b0100000):
        dut.instruction.value = build_instruction(OP_R, 0b000, funct7)
        await Timer(1, unit="ns")
        assert int(dut.weReg.value) == 1
