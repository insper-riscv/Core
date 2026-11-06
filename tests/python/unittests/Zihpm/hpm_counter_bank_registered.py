"""Testes do modulo.

hpm_counter_bank com registered_read: a leitura sai de um registrador, e
o valor do endereco apresentado so aparece um ciclo depois. Os testes
conferem que o valor lido e o dos contadores no ciclo em que o endereco
foi apresentado, que o endereco mudando a cada ciclo mostra o valor do
ciclo anterior e que uma escrita feita a partir do valor lido continua
correta.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

FIRST = 3
EVENT = 4


async def _drive(dut, kind, idx, *write, events=0):
    """Apresenta um acesso sem avancar o clock.

    `write` e vazio ou traz (we, wdata).
    """
    we, wdata = write if write else (0, 0)
    dut.i_idx.value = 0 if kind == "inhibit" else idx
    dut.i_sel_inhibit.value = int(kind == "inhibit")
    dut.i_sel_event.value = int(kind in ("event", "inhibit"))
    dut.i_sel_lo.value = int(kind == "lo")
    dut.i_sel_hi.value = int(kind == "hi")
    dut.i_we.value = we
    dut.i_wdata.value = wdata
    dut.i_events.value = events
    await Timer(1, unit="ns")


async def _clock(dut):
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await _drive(dut, "lo", FIRST)
    dut.i_rst.value = 1
    await _clock(dut)
    await _clock(dut)
    dut.i_rst.value = 0


    """Escolhe o evento EVENT em idx e conta `pulses` ciclos."""
    """Escolhe o evento EVENT para o contador idx e conta pulses ciclos."""
    await _drive(dut, "event", idx, 1, EVENT)
    await _clock(dut)
    for _ in range(pulses):
        await _drive(dut, "lo", idx, events=1 << EVENT)
        await _clock(dut)


@cocotb.test()
async def test_the_value_shows_one_clock_after_the_address(dut):
    """Verifica o valor um ciclo depois do endereco."""
    await _reset(dut)
    await _count(dut, FIRST, 5)
    await _drive(dut, "lo", FIRST)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), 5)


@cocotb.test()
async def test_the_registered_value_is_that_of_the_cycle_of_the_address(dut):
    """Verifica o valor do ciclo em que o endereco foi dado."""
    await _reset(dut)
    await _count(dut, FIRST, 2)
    await _drive(dut, "event", FIRST, 1, EVENT)
    await _clock(dut)
    # o contador conta enquanto o endereco esta apresentado; o valor
    # registrado e o do ciclo da apresentacao, antes do incremento
    await _drive(dut, "lo", FIRST, events=1 << EVENT)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), 2)
    await _drive(dut, "lo", FIRST)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), 3)


@cocotb.test()
async def test_another_index_replaces_the_value_each_clock(dut):
    """Verifica que mudar o endereco troca o valor."""
    await _reset(dut)
    await _count(dut, FIRST, 4)
    await _drive(dut, "lo", FIRST + 1)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), 0)
    await _drive(dut, "lo", FIRST)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), 4)


@cocotb.test()
async def test_a_write_from_the_registered_value_is_exact(dut):
    """Verifica um csrrs sobre o valor registrado."""
    await _reset(dut)
    await _count(dut, FIRST, 3)
    await _drive(dut, "lo", FIRST)
    await _clock(dut)
    old = int(dut.o_rdata.value)
    await _drive(dut, "lo", FIRST, 1, old | 0x10)
    await _clock(dut)
    await _drive(dut, "lo", FIRST)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), 3 | 0x10)


@cocotb.test()
async def test_event_and_inhibit_words_are_registered_too(dut):
    """Verifica mhpmevent e mcountinhibit registrados."""
    await _reset(dut)
    await _drive(dut, "event", FIRST, 1, EVENT)
    await _clock(dut)
    await _drive(dut, "event", FIRST)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), EVENT)
    await _drive(dut, "inhibit", 0, 1, 1 << FIRST)
    await _clock(dut)
    await _drive(dut, "inhibit", 0)
    await _clock(dut)
    check_equal(int(dut.o_rdata.value), 1 << FIRST)
