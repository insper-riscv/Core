"""Testes do modulo.

zicond_unit: czero.eqz zera o resultado quando rs2 vale zero e czero.nez
quando rs2 e diferente de zero; nos demais casos o resultado e rs1.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal, pseudo_random

ALU_CZERO_EQZ = 0b01100
ALU_CZERO_NEZ = 0b01110
MASK32 = 0xFFFFFFFF
# Codigos de operacao da ULA que a unidade nao pode reivindicar.
OTHER_OPS = (
    0b00000, 0b00001, 0b00100, 0b00101, 0b00110, 0b00111, 0b01000,
    0b01010, 0b01011, 0b01101, 0b10000, 0b10001, 0b11000, 0b11001,
    0b11100, 0b11101, 0b11110, 0b11111,
)  # fmt: skip


async def _run(dut, op, rs1, rs2):
    """Aplica os operandos e devolve (ativa, resultado)."""
    dut.i_op.value = op
    dut.i_rs1.value = rs1
    dut.i_rs2.value = rs2
    await Timer(1, unit="ns")
    return int(dut.o_active.value), int(dut.o_result.value)


def _model(op, rs1, rs2):
    """Modelo de referencia da secao 10.1.1 do manual."""
    if op == ALU_CZERO_EQZ:
        return 0 if rs2 == 0 else rs1
    return 0 if rs2 != 0 else rs1


@cocotb.test()
async def test_both_conditions(dut):
    """Verifica a tabela de verdade das duas instrucoes.

    rs2 zero e nao zero, com rs1 igual a zero, a um e a todos os bits.
    """
    for op in (ALU_CZERO_EQZ, ALU_CZERO_NEZ):
        for rs1 in (0, 1, MASK32, 0xDEADBEEF):
            for rs2 in (0, 1, 0x80000000, MASK32):
                got = await _run(dut, op, rs1, rs2)
                want = (1, _model(op, rs1, rs2))
                check_equal(
                    got, want, f"op={op:05b} rs1={rs1:#x} rs2={rs2:#x}"
                )


@cocotb.test()
async def test_every_bit_of_rs2_decides(dut):
    """Verifica que qualquer bit de rs2 o torna diferente de zero.

    Um unico bit em 1, nas 32 posicoes, com rs1 com todos os bits.
    """
    for bit in range(32):
        for op in (ALU_CZERO_EQZ, ALU_CZERO_NEZ):
            got = await _run(dut, op, MASK32, 1 << bit)
            want = (1, _model(op, MASK32, 1 << bit))
            check_equal(got, want, f"op={op:05b} bit={bit}")


@cocotb.test()
async def test_every_bit_of_rs1_passes(dut):
    """Verifica que cada bit de rs1 chega ao resultado.

    Um unico bit de rs1 em 1, com rs2 que deixa o valor passar.
    """
    for bit in range(32):
        got = await _run(dut, ALU_CZERO_EQZ, 1 << bit, 1)
        check_equal(got, (1, 1 << bit), f"eqz bit={bit}")
        got = await _run(dut, ALU_CZERO_NEZ, 1 << bit, 0)
        check_equal(got, (1, 1 << bit), f"nez bit={bit}")


@cocotb.test()
async def test_random_operands(dut):
    """Verifica 200 pares pseudoaleatorios.

    O resultado de cada par coincide com o do modelo.
    """
    values = pseudo_random(7, 400, 32)
    for i in range(200):
        rs1, rs2 = values[2 * i], values[2 * i + 1]
        if i % 4 == 0:
            rs2 = 0
        for op in (ALU_CZERO_EQZ, ALU_CZERO_NEZ):
            got = await _run(dut, op, rs1, rs2)
            check_equal(got, (1, _model(op, rs1, rs2)), f"{rs1:#x} {rs2:#x}")


@cocotb.test()
async def test_other_operations_are_not_claimed(dut):
    """Verifica que os outros codigos da ULA nao a ativam."""
    for op in OTHER_OPS:
        got = await _run(dut, op, MASK32, 1)
        check_equal(got[0], 0, f"op={op:05b} ativou a unidade")
