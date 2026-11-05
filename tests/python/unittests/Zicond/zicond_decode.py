"""Testes do modulo.

zicond_decode: a extensao Zicond reivindica as duas instrucoes R-type
com funct7 = 0000111 e funct3 = 101 (czero.eqz) ou 111 (czero.nez).
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.common.control_unit import build_instruction

OP_R = 0b0110011
OP_IMM = 0b0010011
FUNCT7_ZICOND = 0b0000111
ALU_CZERO_EQZ = 0b01100
ALU_CZERO_NEZ = 0b01110
OUTPUTS = ("o_is_zicond", "o_alu_op", "o_we_reg", "o_sel_pc_rs1")


async def _outputs(dut, instr):
    """Aplica a instrucao e devolve as saidas do decodificador."""
    dut.i_instr.value = instr
    await Timer(1, unit="ns")
    return tuple(int(getattr(dut, n).value) for n in OUTPUTS)


@cocotb.test()
async def test_claims_the_two_instructions(dut):
    """Verifica que czero.eqz e czero.nez sao reivindicadas.

    Cada uma levanta os tres sinais de controle e entrega o seu codigo.
    """
    got = await _outputs(dut, build_instruction(OP_R, 0b101, FUNCT7_ZICOND))
    check_equal(got, (1, ALU_CZERO_EQZ, 1, 1), f"czero.eqz: {got}")
    got = await _outputs(dut, build_instruction(OP_R, 0b111, FUNCT7_ZICOND))
    check_equal(got, (1, ALU_CZERO_NEZ, 1, 1), f"czero.nez: {got}")


@cocotb.test()
async def test_ignores_the_register_fields(dut):
    """Verifica que rd, rs1 e rs2 nao mudam a decisao.

    Os registradores variam em todos os bits, inclusive x0.
    """
    for funct3, code in ((0b101, ALU_CZERO_EQZ), (0b111, ALU_CZERO_NEZ)):
        base = build_instruction(OP_R, funct3, FUNCT7_ZICOND)
        for rd, rs1, rs2 in ((0, 0, 0), (31, 31, 31), (5, 0, 17), (0, 9, 2)):
            instr = base | (rs2 << 20) | (rs1 << 15) | (rd << 7)
            got = await _outputs(dut, instr)
            check_equal(got, (1, code, 1, 1), f"{instr:#010x}: {got}")


@cocotb.test()
async def test_leaves_everything_else_alone(dut):
    """Verifica que o resto do espaco de codificacao nao e reivindicado.

    Os outros funct3 do mesmo funct7, os funct7 vizinhos com os mesmos
    funct3 e os outros opcodes dao tudo zero.
    """
    cases = [(OP_R, f3, FUNCT7_ZICOND) for f3 in (0, 1, 2, 3, 4, 6)]
    cases += [(OP_R, f3, f7) for f3 in (0b101, 0b111) for f7 in (0, 1, 7 ^ 1)]
    cases += [(OP_R, f3, 0b0100000) for f3 in (0b101, 0b111)]
    cases += [(OP_R, f3, 0b1000111) for f3 in (0b101, 0b111)]
    cases += [
        (OP_IMM, 0b101, FUNCT7_ZICOND),
        (OP_IMM, 0b111, FUNCT7_ZICOND),
        (0b0000011, 0b101, FUNCT7_ZICOND),
        (0b1100011, 0b111, FUNCT7_ZICOND),
        (0b0101111, 0b101, FUNCT7_ZICOND),
        (0b0111011, 0b101, FUNCT7_ZICOND),
    ]
    for opcode, funct3, funct7 in cases:
        got = await _outputs(dut, build_instruction(opcode, funct3, funct7))
        check_equal(
            got, (0, 0, 0, 0), f"{opcode:07b}/{funct3:03b}/{funct7:07b}: {got}"
        )
