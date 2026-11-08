"""Testes do modulo.

csr_file com a extensão Sscofpmf: os bits OF e MINH de mhpmeventNh, o
pedido de interrupção de estouro (LCOFI, causa 13), os bits 13 de mip e
mie e a prioridade da interrupção. Os genéricos vêm da entrada do
tests.json: com has_sscofpmf desligado os endereços de mhpmeventNh são
inexistentes e o bit 13 lê zero.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.Zicntr.csr_file_zihpm import (
    access,
    pulses,
    read,
    reset,
    write,
)

MIE, MIP, MSTATUS = 0x304, 0x344, 0x300
EVENT, EVENTH, MLO, MHI = 0x320, 0x720, 0xB00, 0xB80
OF, MINH = 1 << 31, 1 << 30
LCOFI = 1 << 13
CAUSE_LCOFI = 0x8000000D
CAUSE_TIMER = 0x80000007
CODE = 3
WORD_BITS = 32


def _generics(dut):
    """Return (has_sscofpmf, hpm_counters, hpm_width) of the DUT."""
    return (
        bool(int(dut.has_sscofpmf.value)),
        int(dut.hpm_counters.value),
        int(dut.hpm_width.value),
    )


async def _arm(dut, index, remaining):
    """Select the event, set the counter `remaining` below its wrap."""
    _, _, width = _generics(dut)
    await write(dut, EVENT + index, CODE)
    top = (1 << width) - remaining
    await write(dut, MLO + index, top & 0xFFFFFFFF)
    if width > WORD_BITS:
        await write(dut, MHI + index, top >> WORD_BITS)


async def _lines(dut):
    """Return (pending, take, cause) of the interrupt outputs."""
    await Timer(1, unit="ns")
    return (
        int(dut.o_irq_pending.value),
        int(dut.o_irq_take.value),
        int(dut.o_irq_cause.value),
    )


@cocotb.test()
async def test_the_addresses_exist_only_with_the_extension(dut):
    """Verifica mhpmeventNh existe só com a extensão."""
    present, _, _ = _generics(dut)
    await reset(dut)
    for index in (3, 4, 31):
        seen = await access(dut, EVENTH + index, 0b010, 0)
        check_equal(seen[1], 0 if present else 1, hex(EVENTH + index))
        check_equal(seen[0], 0)
    for addr in (0x720, 0x721, 0x722, 0x740):
        check_equal((await access(dut, addr, 0b010, 0))[1], 1, hex(addr))


@cocotb.test()
async def test_bit_13_of_mip_and_mie_only_with_the_extension(dut):
    """Verifica o bit 13 de mie guarda LCOFIE só com a extensão."""
    present, _, _ = _generics(dut)
    await reset(dut)
    await write(dut, MIE, LCOFI)
    check_equal(await read(dut, MIE), LCOFI if present else 0)
    await write(dut, MIE, 0)
    check_equal(await read(dut, MIE), 0)
    check_equal(await read(dut, MIP), 0)


@cocotb.test()
async def test_overflow_sets_of_and_lcofip_and_raises_the_interrupt(dut):
    """Verifica o estouro põe OF e LCOFIP e gera a causa 13."""
    present, _, _ = _generics(dut)
    if not present:
        return
    await reset(dut)
    await _arm(dut, 3, 2)
    check_equal(await read(dut, EVENTH + 3), 0)
    await pulses(dut, CODE, 1)
    await pulses(dut, 0, 4)
    check_equal(await read(dut, EVENTH + 3), 0, "one count short of the wrap")
    await pulses(dut, CODE, 1)
    await pulses(dut, 0, 4)
    check_equal(await read(dut, EVENTH + 3), OF)
    check_equal(await read(dut, MIP), LCOFI)
    check_equal((await _lines(dut))[0], 0, "LCOFIE is still clear")
    await write(dut, MIE, LCOFI)
    pending, take, _ = await _lines(dut)
    check_equal((pending, take), (1, 0), "pending but MIE is zero")
    await write(dut, MSTATUS, 0x8)
    pending, take, cause = await _lines(dut)
    check_equal((pending, take, cause), (1, 1, CAUSE_LCOFI))
    check_equal(await read(dut, EVENT + 3), CODE, "the code is intact")


@cocotb.test()
async def test_a_write_never_overflows_and_of_set_asks_nothing(dut):
    """Verifica que a escrita não estoura e o OF em 1 não pede."""
    present, _, width = _generics(dut)
    if not present:
        return
    await reset(dut)
    await write(dut, EVENT + 3, CODE)
    await write(
        dut, MLO + 3, 0xFFFFFFFF if width >= WORD_BITS else (1 << width) - 1
    )
    if width > WORD_BITS:
        await write(dut, MHI + 3, (1 << (width - WORD_BITS)) - 1)
    await pulses(dut, 0, 4)
    check_equal(await read(dut, EVENTH + 3), 0, "a write overflowed")
    check_equal(await read(dut, MIP), 0)
    # Software sets OF (the interrupt is disabled for this counter): the
    # overflow asks for nothing.
    await write(dut, EVENTH + 3, OF)
    await pulses(dut, CODE, 1)
    await pulses(dut, 0, 4)
    check_equal(await read(dut, EVENTH + 3), OF)
    check_equal(await read(dut, MIP), 0, "OF = 1 must not ask")
    # Clearing OF and re-arming asks again.
    await write(dut, EVENTH + 3, 0)
    await _arm(dut, 3, 1)
    await pulses(dut, CODE, 1)
    await pulses(dut, 0, 4)
    check_equal(await read(dut, EVENTH + 3), OF)
    check_equal(await read(dut, MIP), LCOFI)
    # LCOFIP is cleared by a write to mip, and OF is only cleared by its
    # own write.
    await write(dut, MIP, 0)
    check_equal(await read(dut, MIP), 0)
    check_equal(await read(dut, EVENTH + 3), OF)


@cocotb.test()
async def test_minh_stops_the_counting(dut):
    """Verifica MINH impede a contagem no modo máquina."""
    present, _, _ = _generics(dut)
    if not present:
        return
    await reset(dut)
    await write(dut, EVENT + 4, CODE)
    await write(dut, EVENTH + 4, MINH)
    check_equal(await read(dut, EVENTH + 4), MINH)
    await pulses(dut, CODE, 3)
    check_equal(await read(dut, MLO + 4), 0)
    await write(dut, EVENTH + 4, 0)
    await pulses(dut, CODE, 3)
    await pulses(dut, 0, 1)
    check_equal(await read(dut, MLO + 4), 3)


@cocotb.test()
async def test_lcofi_has_the_lowest_priority(dut):
    """Verifica a ordem externa, software, timer e estouro."""
    present, _, _ = _generics(dut)
    if not present:
        return
    await reset(dut)
    await _arm(dut, 5, 1)
    await write(dut, MIE, LCOFI | (1 << 7))
    await write(dut, MSTATUS, 0x8)
    await pulses(dut, CODE, 1)
    await pulses(dut, 0, 4)
    check_equal((await _lines(dut))[2], CAUSE_LCOFI)
    dut.i_irq_timer.value = 1
    check_equal((await _lines(dut))[2], CAUSE_TIMER, "timer beats LCOFI")
    dut.i_irq_timer.value = 0
    check_equal((await _lines(dut))[2], CAUSE_LCOFI)


@cocotb.test()
async def test_absent_counters_read_zero_in_the_high_selector(dut):
    """Verifica que os índices sem contador leem zero."""
    present, counters, _ = _generics(dut)
    if not present:
        return
    await reset(dut)
    for index in range(3 + counters, 32):
        check_equal((await write(dut, EVENTH + index, OF | MINH))[1], 0)
        check_equal(await read(dut, EVENTH + index), 0, index)
    check_true(counters >= 1)
