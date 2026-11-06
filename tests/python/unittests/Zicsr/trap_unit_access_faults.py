"""Testes do modulo.

trap_unit com has_access_faults: a busca fora de região executável gera a causa 1 (mtval = PC), o load que o mapa
não aceita ler gera a causa 5 e o store que o mapa não aceita escrever gera a causa 7 (mtval = endereço efetivo).
Prioridade da Tabela 17: a falha de busca vem antes da instrução ilegal, que vem antes da falha de dados, e a falha
de acesso de dados vem antes do desalinhamento. Sem falha os acessos seguem como antes.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.trap_unit import (
    OP_ALU,
    OP_LOAD,
    OP_STORE,
    probe,
)

LW, SW, SH = 0b010, 0b010, 0b001


async def drive(dut, opcode, funct3=0, fetch_ok=1, pc=0x1234, rd_ok=1, wr_ok=1, **kw):
    """Apresenta uma instrução com as marcas de validade do mapa."""
    dut.i_fetch_ok.value = fetch_ok
    dut.i_pc.value = pc
    dut.i_ea_rd_ok.value = rd_ok
    dut.i_ea_wr_ok.value = wr_ok
    return await probe(dut, opcode, funct3, **kw)


@cocotb.test()
async def test_fetch_fault_is_cause_1_with_the_pc(dut):
    """Verifica a busca inválida gera causa 1 com mtval = PC, mesmo numa ALU."""
    check_equal(await drive(dut, OP_ALU, fetch_ok=0, pc=0x9000_0010), (1, 0, 1, 0x9000_0010))
    check_equal((await drive(dut, OP_ALU, fetch_ok=1))[0], 0)
    check_equal((await drive(dut, OP_ALU, fetch_ok=0, valid=0))[0], 0)
    check_equal((await drive(dut, OP_ALU, fetch_ok=0, run=0))[0], 0)


@cocotb.test()
async def test_load_and_store_faults(dut):
    """Verifica a causa 5 no load e a 7 no store, com mtval = endereço."""
    check_equal(await drive(dut, OP_LOAD, LW, rd_ok=0, ea=0x2000_0000), (1, 0, 5, 0x2000_0000))
    check_equal((await drive(dut, OP_LOAD, LW, rd_ok=1, wr_ok=0, ea=0x2000_0000))[0], 0)
    check_equal(await drive(dut, OP_STORE, SW, wr_ok=0, ea=0x10), (1, 0, 7, 0x10))
    check_equal((await drive(dut, OP_STORE, SW, wr_ok=1, rd_ok=0, ea=0x10))[0], 0)


@cocotb.test()
async def test_priorities(dut):
    """Verifica fetch, ilegal, falha de dados e desalinhamento, nessa ordem."""
    # falha de busca vence a instrução ilegal e o alvo desalinhado
    check_equal((await drive(dut, OP_ALU, fetch_ok=0, illegal=1))[2], 1)
    check_equal((await drive(dut, OP_ALU, fetch_ok=0, cf_taken=1, cf_target=2))[2], 1)
    # ilegal vence a falha de dados: o decodificador marca o load como ilegal (funct3 reservado)
    check_equal((await drive(dut, OP_LOAD, 0b011, rd_ok=0, illegal=1, ea=4))[2:], (2, 0))
    # a falha de acesso vence o desalinhamento (halfword no offset 1, fora da memória principal)
    check_equal(await drive(dut, OP_STORE, SH, wr_ok=0, ea=0x1), (1, 0, 7, 0x1))
    check_equal(await drive(dut, OP_LOAD, LW, rd_ok=0, ea=0x2), (1, 0, 5, 0x2))


@cocotb.test()
async def test_no_fault_keeps_the_behaviour(dut):
    """Verifica sem falha o acesso desalinhado ainda gera 4 e 6."""
    await Timer(1, unit="ns")
    check_equal((await drive(dut, OP_ALU))[0], 0)
    check_equal((await drive(dut, OP_LOAD, LW, ea=0x10))[0], 0)
