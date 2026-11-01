"""Testes do modulo.

csr_decode: Zicsr claims the SYSTEM class; funct3 other than 000 and 100
are CSR accesses.
"""

import cocotb
from cocotb.triggers import Timer

OP_SYSTEM = 0b1110011
OUTPUTS = ("o_is_csr", "o_we_reg", "o_use_imm_i")


def _instr(opcode, funct3, csr=0x300, rd=1, rs1=2):
    return (csr << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


async def _outputs(dut, instr):
    dut.i_instr.value = instr
    await Timer(1, unit="ns")
    return tuple(int(getattr(dut, n).value) for n in OUTPUTS)


@cocotb.test()
async def test_claims_every_csr_instruction(dut):
    """Verifica claims every csr instruction.

    CSRRW, CSRRS, CSRRC and the three immediate forms raise all outputs.
    """
    for funct3 in (0b001, 0b010, 0b011, 0b101, 0b110, 0b111):
        got = await _outputs(dut, _instr(OP_SYSTEM, funct3))
        assert got == (1, 1, 1), f"funct3={funct3:03b}: {got}"


@cocotb.test()
async def test_other_system_instructions_only_fetch_the_csr_field(dut):
    """Verifica other system instructions only fetch the csr field.

    ECALL, EBREAK, MRET, WFI (funct3 = 000) and the reserved funct3 =
    100 raise only useImmI.
    """
    cases = [
        _instr(OP_SYSTEM, 0b000, csr=0x000, rd=0, rs1=0),  # ecall
        _instr(OP_SYSTEM, 0b000, csr=0x001, rd=0, rs1=0),  # ebreak
        _instr(OP_SYSTEM, 0b000, csr=0x302, rd=0, rs1=0),  # mret
        _instr(OP_SYSTEM, 0b000, csr=0x105, rd=0, rs1=0),  # wfi
        _instr(OP_SYSTEM, 0b100),
    ]
    for instr in cases:
        got = await _outputs(dut, instr)
        assert got == (0, 0, 1), f"{instr:#010x}: {got}"


@cocotb.test()
async def test_leaves_everything_else_alone(dut):
    """Other opcodes: all outputs zero."""
    cases = [
        _instr(0b0110011, 0b001),  # sll
        _instr(0b0010011, 0b001),  # slli
        _instr(0b0001111, 0b001),  # fence.i
    ]
    for instr in cases:
        got = await _outputs(dut, instr)
        assert got == (0, 0, 0), f"{instr:#010x}: {got}"
