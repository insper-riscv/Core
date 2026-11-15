"""Testes do modulo.

Testes da forwarding_unit: seleção da fonte do adiantamento a partir dos
casamentos, já condicionados à validade das instruções à frente.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

# Posição de cada casamento no vetor (FWD_MATCH_* de fwd_consts).
EXMEM, MEMWB, WB2 = 0, 1, 2
# Códigos do seletor (FWD_* de fwd_consts).
NONE, SEL_MEMWB, SEL_EXMEM, SEL_WB2 = 0, 1, 2, 3


def expected(match: int) -> int:
    """Executa expected.

    Modelo de referência: a fonte mais nova que casa.
    """
    if (match >> EXMEM) & 1:
        return SEL_EXMEM
    if (match >> MEMWB) & 1:
        return SEL_MEMWB
    if (match >> WB2) & 1:
        return SEL_WB2
    return NONE


async def apply(dut, matches):
    """Aplica os casamentos e espera a propagação combinacional."""
    match_rs1, match_rs2 = matches
    dut.i_match_rs1.value = match_rs1
    dut.i_match_rs2.value = match_rs2
    await Timer(1, unit="ns")


@cocotb.test()
async def test_exhaustive_truth_table(dut):
    """Verifica exhaustive truth table.

    Todas as combinações de casamentos dos dois operandos batem com o
    modelo.
    """
    for m1 in range(8):
        for m2 in range(8):
            await apply(dut, (m1, m2))
            check_equal(int(dut.o_fwd_rs1.value), expected(m1), (m1, m2))
            check_equal(int(dut.o_fwd_rs2.value), expected(m2), (m1, m2))


@cocotb.test()
async def test_no_match_selects_register_file(dut):
    """Verifica no match selects register file.

    Sem casamento o operando vem do banco de registradores.
    """
    await apply(dut, (0, 0))
    check_equal(int(dut.o_fwd_rs1.value), NONE)
    check_equal(int(dut.o_fwd_rs2.value), NONE)


@cocotb.test()
async def test_newest_match_wins(dut):
    """Verifica newest match wins.

    Com os três casamentos, vale EX/MEM; sem ele, MEM/WB; sem os dois,
    WB2.
    """
    await apply(dut, (0b111, 0b111))
    check_equal(int(dut.o_fwd_rs1.value), SEL_EXMEM)
    await apply(dut, (0b110, 0b110))
    check_equal(int(dut.o_fwd_rs1.value), SEL_MEMWB)
    await apply(dut, (0b100, 0b100))
    check_equal(int(dut.o_fwd_rs1.value), SEL_WB2)


@cocotb.test()
async def test_operands_are_independent(dut):
    """Verifica operands are independent.

    Os dois operandos escolhem a fonte cada um com os seus casamentos.
    """
    await apply(dut, (1 << EXMEM, 1 << WB2))
    check_equal(int(dut.o_fwd_rs1.value), SEL_EXMEM)
    check_equal(int(dut.o_fwd_rs2.value), SEL_WB2)
