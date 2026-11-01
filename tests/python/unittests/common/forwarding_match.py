"""Testes do modulo.

Testes da forwarding_match: casamento dos operandos de ID com os
destinos das três instruções à frente.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import Prng, check_equal

# Posição de cada casamento no vetor (FWD_MATCH_* de fwd_consts).
EXMEM, MEMWB, WB2 = 0, 1, 2


def expected(rs: int, ahead: list[tuple[int, int]]) -> int:
    """Executa expected.

    Modelo de referência: um bit por instrução à frente que escreve em
    rs, exceto x0.
    """
    bits = 0
    for position, (rd, we) in enumerate(ahead):
        if we and rd != 0 and rd == rs:
            bits |= 1 << position
    return bits


async def apply(dut, sources, ex, mem, wb):
    """Executa apply.

    Aplica as entradas (destino e escrita de ID/EX, EX/MEM e MEM/WB) e
    espera a propagação.
    """
    rs1, rs2 = sources
    dut.i_rs1.value = rs1
    dut.i_rs2.value = rs2
    dut.i_ex_rd.value, dut.i_ex_we.value = ex
    dut.i_mem_rd.value, dut.i_mem_we.value = mem
    dut.i_wb_rd.value, dut.i_wb_we.value = wb
    await Timer(1, unit="ns")


async def check(dut, sources, ex, mem, wb):
    """Aplica as entradas e compara as duas saídas com o modelo."""
    rs1, rs2 = sources
    await apply(dut, sources, ex, mem, wb)
    ahead = [ex, mem, wb]
    check_equal(
        int(dut.o_match_rs1.value),
        expected(rs1, ahead),
        (
            rs1,
            rs2,
            ex,
            mem,
            wb,
        ),
    )
    check_equal(
        int(dut.o_match_rs2.value),
        expected(rs2, ahead),
        (
            rs1,
            rs2,
            ex,
            mem,
            wb,
        ),
    )


@cocotb.test()
async def test_every_register_matches_each_position(dut):
    """Verifica every register matches each position.

    Cada registrador x1 a x31 casa com a posição que o escreve, e só com
    ela.
    """
    for reg in range(1, 32):
        for position in (EXMEM, MEMWB, WB2):
            ahead = [(0, 0), (0, 0), (0, 0)]
            ahead[position] = (reg, 1)
            await check(dut, (reg, reg), *ahead)
            check_equal(int(dut.o_match_rs1.value), 1 << position)


@cocotb.test()
async def test_x0_never_matches(dut):
    """Verifica x0 never matches.

    Um destino x0 não casa, mesmo escrevendo e com o operando também em
    x0.
    """
    await check(dut, (0, 0), (0, 1), (0, 1), (0, 1))
    check_equal(int(dut.o_match_rs1.value), 0)
    check_equal(int(dut.o_match_rs2.value), 0)


@cocotb.test()
async def test_no_write_never_matches(dut):
    """Verifica no write never matches.

    Sem habilitação de escrita não há casamento, mesmo com o registrador
    igual.
    """
    await check(dut, (5, 5), (5, 0), (5, 0), (5, 0))
    check_equal(int(dut.o_match_rs1.value), 0)


@cocotb.test()
async def test_all_positions_can_match_together(dut):
    """Os três destinos iguais ao operando acendem os três bits."""
    await check(dut, (9, 4), (9, 1), (9, 1), (9, 1))
    check_equal(int(dut.o_match_rs1.value), 0b111)
    check_equal(int(dut.o_match_rs2.value), 0)


@cocotb.test()
async def test_random_against_the_model(dut):
    """Verifica random against the model.

    Combinações aleatórias, com poucos registradores para forçar
    colisões, batem com o modelo.
    """
    rng = Prng(7)
    for _ in range(2000):
        regs = [rng.randrange(0, 5) for _ in range(5)]
        wes = [rng.randrange(2) for _ in range(3)]
        await check(
            dut,
            (regs[0], regs[1]),
            (regs[2], wes[0]),
            (regs[3], wes[1]),
            (regs[4], wes[2]),
        )
