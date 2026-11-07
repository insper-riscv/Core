"""Testes do modulo.

csr_file com time_external: os CSRs time (0xC01) e timeh (0xC81) são o sombreamento somente leitura do mtime que a
plataforma entrega em i_mtime. Eles seguem o valor da porta a cada ciclo (também quando o mtime é reescrito), não
aceitam escrita, e o contador próprio e o divisor de tick não existem.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicntr.csr_file_zihpm import (
    access,
    read,
    reset,
    write,
)

TIME, TIMEH = 0xC01, 0xC81


@cocotb.test()
async def test_time_follows_the_mtime_port(dut):
    """Verifica time e timeh leem a porta i_mtime, inclusive saltos."""
    await reset(dut)
    for value in (0, 1, 0xFFFFFFFF, 0x1_0000_0000, 0x0123_4567_89AB_CDEF, (1 << 64) - 1):
        dut.i_mtime.value = value
        await Timer(1, unit="ns")
        check_equal(await read(dut, TIME), value & 0xFFFFFFFF, hex(value))
        check_equal(await read(dut, TIMEH), value >> 32, hex(value))


@cocotb.test()
async def test_time_does_not_count_by_itself(dut):
    """Verifica sem mudança em i_mtime o time não anda."""
    await reset(dut)
    dut.i_mtime.value = 42
    first = await read(dut, TIME)
    for _ in range(200):
        await Timer(10, unit="ns")
    check_equal(await read(dut, TIME), first)


@cocotb.test()
async def test_time_is_read_only(dut):
    """Verifica a escrita em time e timeh é ilegal e não muda o valor."""
    await reset(dut)
    dut.i_mtime.value = 7
    for addr in (TIME, TIMEH):
        check_equal((await write(dut, addr, 99))[1], 1, hex(addr))
        check_equal((await access(dut, addr, 0b010, 0))[1], 0, hex(addr))
    check_equal(await read(dut, TIME), 7)
