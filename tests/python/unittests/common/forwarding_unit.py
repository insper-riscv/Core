"""Testes do modulo.

Testes da forwarding_unit: seleção da fonte a partir dos casamentos
registrados e da validade.
"""

import itertools

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

# Posição de cada casamento no vetor (FWD_MATCH_* de fwd_consts).
EXMEM, MEMWB, WB2 = 0, 1, 2
# Códigos do seletor (FWD_* de fwd_consts).
NONE, SEL_MEMWB, SEL_EXMEM, SEL_WB2 = 0, 1, 2, 3


def expected(match: int, exmem_ok: int, memwb_ok: int, wb2_ok: int) -> int:
    """Executa expected.

    Modelo de referência: a fonte mais nova que casa e ainda é válida.
    """
    if (match >> EXMEM) & 1 and exmem_ok:
        return SEL_EXMEM
    if (match >> MEMWB) & 1 and memwb_ok:
        return SEL_MEMWB
    if (match >> WB2) & 1 and wb2_ok:
        return SEL_WB2
    return NONE


async def apply(dut, matches, oks):
    """Aplica as entradas e espera a propagação combinacional."""
    match_rs1, match_rs2 = matches
    exmem_ok, memwb_ok, wb2_ok = oks
    dut.i_match_rs1.value = match_rs1
    dut.i_match_rs2.value = match_rs2
    dut.i_exmem_ok.value = exmem_ok
    dut.i_memwb_ok.value = memwb_ok
    dut.i_wb2_ok.value = wb2_ok
    await Timer(1, unit="ns")


@cocotb.test()
async def test_exhaustive_truth_table(dut):
    """Verifica exhaustive truth table.

    Todas as combinações de casamentos e validades dos dois operandos
    batem com o modelo.
    """
    for m1, m2, e_ok, m_ok, w_ok in itertools.product(
        range(8), range(8), range(2), range(2), range(2)
    ):
        await apply(dut, (m1, m2), (e_ok, m_ok, w_ok))
        check_equal(
            int(dut.o_fwd_rs1.value),
            expected(m1, e_ok, m_ok, w_ok),
            (
                m1,
                m2,
                e_ok,
                m_ok,
                w_ok,
            ),
        )
        check_equal(
            int(dut.o_fwd_rs2.value),
            expected(m2, e_ok, m_ok, w_ok),
            (
                m1,
                m2,
                e_ok,
                m_ok,
                w_ok,
            ),
        )


@cocotb.test()
async def test_no_match_selects_register_file(dut):
    """Verifica no match selects register file.

    Sem casamento o operando vem do banco de registradores, mesmo com
    tudo válido.
    """
    await apply(dut, (0, 0), (1, 1, 1))
    check_equal(int(dut.o_fwd_rs1.value), NONE)
    check_equal(int(dut.o_fwd_rs2.value), NONE)


@cocotb.test()
async def test_newest_valid_match_wins(dut):
    """Verifica newest valid match wins.

    Com os três casamentos, vale EX/MEM; descartada a mais nova, cai
    para a seguinte.
    """
    await apply(dut, (0b111, 0b111), (1, 1, 1))
    check_equal(int(dut.o_fwd_rs1.value), SEL_EXMEM)
    await apply(dut, (0b111, 0b111), (0, 1, 1))
    check_equal(int(dut.o_fwd_rs1.value), SEL_MEMWB)
    await apply(dut, (0b111, 0b111), (0, 0, 1))
    check_equal(int(dut.o_fwd_rs1.value), SEL_WB2)
    await apply(dut, (0b111, 0b111), (0, 0, 0))
    check_equal(int(dut.o_fwd_rs1.value), NONE)


@cocotb.test()
async def test_operands_are_independent(dut):
    """Verifica operands are independent.

    Os dois operandos escolhem a fonte cada um com os seus casamentos.
    """
    await apply(dut, (1 << EXMEM, 1 << WB2), (1, 1, 1))
    check_equal(int(dut.o_fwd_rs1.value), SEL_EXMEM)
    check_equal(int(dut.o_fwd_rs2.value), SEL_WB2)
