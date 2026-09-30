"""m_decode: the M extension claims R-type instructions with funct7 = 0000001."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.common.control_unit import build_instruction

OP_R = 0b0110011
OP_IMM = 0b0010011
OUTPUTS = ("isMulDiv", "weReg", "selPCRS1")


async def _outputs(dut, instr):
    dut.instruction.value = instr
    await Timer(1, unit="ns")
    return tuple(int(getattr(dut, n).value) for n in OUTPUTS)


@cocotb.test()
async def test_claims_every_m_instruction(dut):
    """MUL..REMU (all funct3 of funct7 = 0000001) raise all three outputs."""
    for funct3 in range(8):
        got = await _outputs(dut, build_instruction(OP_R, funct3, 0b0000001))
        assert got == (1, 1, 1), f"funct3={funct3}: {got}"


@cocotb.test()
async def test_leaves_everything_else_alone(dut):
    """Base R-type, other funct7, and other opcodes: all outputs zero."""
    cases = [
        (OP_R, 0b000, 0b0000000),  # add
        (OP_R, 0b000, 0b0100000),  # sub
        (OP_R, 0b101, 0b0100000),  # sra
        (OP_IMM, 0b000, 0b0000001),  # addi whose immediate bits look like funct7 = 1
        (0b0000011, 0b010, 0b0000001),  # lw
        (0b0100011, 0b010, 0b0000001),  # sw
        (0b1100011, 0b000, 0b0000001),  # beq
    ]
    for opcode, funct3, funct7 in cases:
        got = await _outputs(dut, build_instruction(opcode, funct3, funct7))
        assert got == (0, 0, 0), f"{opcode:07b}/{funct3}/{funct7:07b}: {got}"
