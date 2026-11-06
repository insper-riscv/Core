"""Testes do modulo.

Prioridade entre as interrupções de máquina: com externa, software e
timer pendentes e habilitadas ao mesmo tempo, o núcleo as toma na ordem
externa (0x8000000B), software (0x80000003) e timer (0x80000007), todas
sobre a mesma instrução, que só executa depois da última.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.cores.irq_common import (
    CAUSE_EXTERNAL,
    CAUSE_SOFTWARE,
    CAUSE_TIMER,
    EXTERNAL,
    SOFTWARE,
    TIMER,
    check_count,
    check_sweep,
    run_sweep,
)

GAPS = (3, 17, 8, 0, 23, 5)
ORDER = [CAUSE_EXTERNAL, CAUSE_SOFTWARE, CAUSE_TIMER]


@cocotb.test()
async def test_priority_external_software_timer(dut):
    """Verifica a ordem externa, software e timer sobre o mesmo mepc."""
    ram, prog, entries = await run_sweep(
        dut,
        0,
        0xC0FFEE,
        GAPS,
        enable=SOFTWARE | TIMER | EXTERNAL,
        held=(SOFTWARE, TIMER, EXTERNAL),
        masked=(),
    )
    check_sweep(ram, prog, entries)
    check_count(entries, 30)
    check_equal(len(entries) % 3, 0)
    for first in range(0, len(entries), 3):
        last = first + 3
        group = entries[first:last]
        check_equal([cause for cause, _, _ in group], ORDER)
        check_equal(len({epc for _, epc, _ in group}), 1, "mepc mudou")
        check_equal(len({x10 for _, _, x10 in group}), 1, "x10 mudou")


@cocotb.test()
async def test_software_alone_has_its_cause(dut):
    """Verifica que só a linha de software dá a causa 0x80000003."""
    ram, prog, entries = await run_sweep(
        dut, 0, 0xFACADE, GAPS, enable=SOFTWARE, held=(SOFTWARE,), masked=()
    )
    check_sweep(ram, prog, entries)
    check_count(entries, 10)
    check_equal({cause for cause, _, _ in entries}, {CAUSE_SOFTWARE})


@cocotb.test()
async def test_external_alone_has_its_cause(dut):
    """Verifica que a linha externa sozinha dá a causa 0x8000000B."""
    ram, prog, entries = await run_sweep(
        dut, 0, 0xFACADE, GAPS, enable=EXTERNAL, held=(EXTERNAL,), masked=()
    )
    check_sweep(ram, prog, entries)
    check_count(entries, 10)
    check_equal({cause for cause, _, _ in entries}, {CAUSE_EXTERNAL})
