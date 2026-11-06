"""Testes de muldiv_fusion: registro da última operação M e acerto.

O acerto exige registro válido, operandos iguais, mesma família
(multiplicação, DIV/REM ou DIVU/REMU) e operação diferente; sobe no
ciclo seguinte ao início e o o_fuse sai um ciclo depois.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

A, B = 0x12345678, 0x0F0F0F0F
LO, HI = 0xCAFEF00D, 0xDEADBEEF


def expected_hit(recorded, current):
    """Modelo do acerto para o funct3 registrado e o funct3 atual."""
    if recorded == current or (recorded >> 2) != (current >> 2):
        return 0
    return int(current >> 2 == 0 or (recorded & 1) == (current & 1))


async def start(dut):
    """Liga o clock e aplica reset, sem operação registrada."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await reset(dut)


async def reset(dut):
    """Zera as entradas e aplica reset por dois ciclos."""
    for name in ("start", "done", "funct3", "done_funct3", "a", "b"):
        getattr(dut, f"i_{name}").value = 0
    dut.i_full_lo.value = 0
    dut.i_full_hi.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def edge(dut):
    """Avança uma borda de clock e espera o assentamento."""
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def record(dut, operands, funct3):
    """Conclui uma operação, gravando operandos, funct3 e resultado."""
    dut.i_a.value, dut.i_b.value = operands
    dut.i_done_funct3.value = funct3
    dut.i_full_lo.value = LO
    dut.i_full_hi.value = HI
    dut.i_done.value = 1
    await edge(dut)
    dut.i_done.value = 0


async def probe(dut, operands, funct3):
    """Inicia uma instrução e devolve (hit antes, hit, fuse, depois)."""
    dut.i_a.value, dut.i_b.value = operands
    dut.i_funct3.value = funct3
    dut.i_start.value = 1
    await Timer(1, unit="ns")
    early = int(dut.o_hit.value)
    await edge(dut)
    dut.i_start.value = 0
    await Timer(1, unit="ns")
    hit = int(dut.o_hit.value)
    await edge(dut)
    fuse = int(dut.o_fuse.value)
    await edge(dut)
    return early, hit, fuse, int(dut.o_fuse.value)


@cocotb.test()
async def test_no_hit_before_first_operation(dut):
    """Sem operação registrada nunca há acerto."""
    await start(dut)
    for funct3 in range(8):
        check_equal(await probe(dut, (A, B), funct3), (0, 0, 0, 0), funct3)


@cocotb.test()
async def test_pairing_rule(dut):
    """Todos os pares de funct3 batem com a regra da família."""
    await start(dut)
    for recorded in range(8):
        await record(dut, (A, B), recorded)
        for current in range(8):
            hit = expected_hit(recorded, current)
            seen = await probe(dut, (A, B), current)
            check_equal(seen, (0, hit, hit, 0), (recorded, current))


@cocotb.test()
async def test_operands_compared_by_value(dut):
    """Operandos diferentes (A ou B) não fundem."""
    await start(dut)
    await record(dut, (A, B), 0)
    for operands in ((A ^ 1, B), (A, B ^ 0x80000000), (B, A)):
        check_equal(await probe(dut, operands, 1), (0, 0, 0, 0), operands)
    check_equal(await probe(dut, (A, B), 1), (0, 1, 1, 0), "iguais")


@cocotb.test()
async def test_record_holds_full_result(dut):
    """O registro guarda o resultado completo e só muda com i_done."""
    await start(dut)
    await record(dut, (A, B), 4)
    check_equal(int(dut.o_rec_lo.value), LO, "baixa")
    check_equal(int(dut.o_rec_hi.value), HI, "alta")
    dut.i_full_lo.value = 0x11111111
    dut.i_full_hi.value = 0x22222222
    await edge(dut)
    check_equal(int(dut.o_rec_lo.value), LO, "baixa sem done")
    check_equal(int(dut.o_rec_hi.value), HI, "alta sem done")


@cocotb.test()
async def test_reset_invalidates_record(dut):
    """O reset invalida o registro e zera o resultado guardado."""
    await start(dut)
    await record(dut, (A, B), 0)
    await reset(dut)
    check_equal(int(dut.o_rec_lo.value), 0, "baixa")
    check_equal(int(dut.o_rec_hi.value), 0, "alta")
    check_equal(await probe(dut, (A, B), 1), (0, 0, 0, 0), "depois do reset")
