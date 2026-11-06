"""Testes do modulo.

Interrupção de timer com FENCE.I no programa (extensão Zifencei): o
FENCE.I redireciona o pipeline para a instrução seguinte, então a
interrupção não o aborta; ela é tomada na instrução seguinte, e todo
FENCE.I completa exatamente uma vez.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.irq_common import (
    CAUSE_TIMER,
    check_count,
    check_sweep,
    covered_kinds,
    emit_fencei,
    run_sweep,
)

GAPS = (0, 1, 2, 3, 0, 5, 1, 4, 2)
EXTRA = (emit_fencei,) * 6


@cocotb.test()
async def test_timer_around_fence_i(dut):
    """Verifica a interrupção entre e sobre FENCE.I, sem repeti-lo."""
    ram, prog, entries = await run_sweep(dut, 0, 0x5EED, GAPS, extra=EXTRA)
    check_sweep(ram, prog, entries)
    for cause, _, _ in entries:
        check_equal(cause, CAUSE_TIMER)
    check_count(entries, 41)
    kinds = covered_kinds(prog, entries)
    check_true("fencei" not in kinds, "FENCE.I foi abortado por interrupção")
    check_true("inc" in kinds)
