"""Testes do modulo.

FENCE.I with a write-back data cache: the store of the new instruction
is dirty in the cache.

The core asks the data cache for a flush, holds the FENCE.I in EX until
the cache answers, and only then invalidates the instruction cache. The
model of the data cache keeps stores dirty until the flush, so the
instruction cache fills the new instruction only if the core waited for
it.
"""

import cocotb

from tests.python.unittests.cores.FenceI import FENCE_I, NOP, run


@cocotb.test()
async def test_fence_i_flushes_the_data_cache_first(dut):
    """Verifica fence i flushes the data cache first."""
    for latency in (-1, 0, 1, 4, 20):
        ram, (pulses, flushes) = await run(dut, FENCE_I, flush_latency=latency)
        assert ram.get(0x8004) == 1, f"first run, flush latency {latency}"
        assert ram.get(0x8000) == 2, (
            f"the rewritten instruction did not run (flush latency {latency})"
        )
        assert pulses == 1 and flushes == 1, (pulses, flushes)


@cocotb.test()
async def test_without_fence_i_the_dirty_store_is_not_seen(dut):
    """Verifica without fence i the dirty store is not seen."""
    ram, (pulses, flushes) = await run(dut, NOP, flush_latency=4)
    assert ram.get(0x8000) == 1
    assert pulses == 0 and flushes == 0
