"""Testes do modulo.

trap_unit com HAS_ACCESS_FAULTS: a busca fora de região executável gera
a causa 1 (mtval = PC), o load que o mapa não aceita ler gera a causa 5
e o store que o mapa não aceita escrever gera a causa 7 (mtval =
endereço efetivo). Prioridade da Tabela 17: a falha de busca vem antes
da instrução ilegal, que vem antes da falha de dados; o desalinhamento
que o hardware não executa (fora da memória principal) mantém a causa 4
ou 6 (a ordem opcional do manual). Sem falha os acessos seguem como
antes.
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


async def drive(dut, opcode, funct3=0, **kw):
    """Apresenta uma instrução com as marcas de validade do mapa.

    As chaves fetch_ok, pc, rd_ok e wr_ok ajustam as marcas do mapa e
    as demais seguem para o sonda do trap_unit.
    """
    dut.i_fetch_ok.value = kw.pop("fetch_ok", 1)
    dut.i_pc.value = kw.pop("pc", 0x1234)
    dut.i_ea_rd_ok.value = kw.pop("rd_ok", 1)
    dut.i_ea_wr_ok.value = kw.pop("wr_ok", 1)
    return await probe(dut, opcode, funct3, **kw)


@cocotb.test()
async def test_fetch_fault_is_cause_1_with_the_pc(dut):
    """Verifica a busca inválida gera a causa 1 com mtval = PC."""
    check_equal(
        await drive(dut, OP_ALU, fetch_ok=0, pc=0x9000_0010),
        (1, 0, 1, 0x9000_0010),
    )
    check_equal((await drive(dut, OP_ALU, fetch_ok=1))[0], 0)
    check_equal((await drive(dut, OP_ALU, fetch_ok=0, valid=0))[0], 0)
    check_equal((await drive(dut, OP_ALU, fetch_ok=0, run=0))[0], 0)


@cocotb.test()
async def test_load_and_store_faults(dut):
    """Verifica a causa 5 no load e a 7 no store, mtval = endereço."""
    check_equal(
        await drive(dut, OP_LOAD, LW, rd_ok=0, ea=0x2000_0000),
        (1, 0, 5, 0x2000_0000),
    )
    check_equal(
        (await drive(dut, OP_LOAD, LW, rd_ok=1, wr_ok=0, ea=0x2000_0000))[0], 0
    )
    check_equal(
        await drive(dut, OP_STORE, SW, wr_ok=0, ea=0x10), (1, 0, 7, 0x10)
    )
    check_equal(
        (await drive(dut, OP_STORE, SW, wr_ok=1, rd_ok=0, ea=0x10))[0], 0
    )


@cocotb.test()
async def test_priorities(dut):
    """Verifica a ordem fetch, ilegal, dados e desalinhamento."""
    # falha de busca vence a instrução ilegal e o alvo desalinhado
    check_equal((await drive(dut, OP_ALU, fetch_ok=0, illegal=1))[2], 1)
    check_equal(
        (await drive(dut, OP_ALU, fetch_ok=0, cf_taken=1, cf_target=2))[2], 1
    )
    # ilegal vence a falha de dados: o decodificador marca o load como
    # ilegal (funct3 reservado)
    check_equal(
        (await drive(dut, OP_LOAD, 0b011, rd_ok=0, illegal=1, ea=4))[2:],
        (2, 0),
    )
    # o desalinhamento fora da memória principal mantém a causa 4 ou 6,
    # mesmo com o mapa recusando o endereço
    check_equal(
        await drive(dut, OP_STORE, 0b010, wr_ok=0, ea=0x2), (1, 0, 6, 0x2)
    )
    check_equal(await drive(dut, OP_LOAD, LW, rd_ok=0, ea=0x2), (1, 0, 4, 0x2))
    # o desalinhado que o hardware executa (na memória principal) com
    # endereço recusado dá a falha de acesso
    check_equal(
        await drive(dut, OP_LOAD, LW, rd_ok=0, ea=0x9001), (1, 0, 5, 0x9001)
    )


@cocotb.test()
async def test_no_fault_keeps_the_behaviour(dut):
    """Verifica sem falha o acesso desalinhado ainda gera 4 e 6."""
    await Timer(1, unit="ns")
    check_equal((await drive(dut, OP_ALU))[0], 0)
    check_equal((await drive(dut, OP_LOAD, LW, ea=0x10))[0], 0)
