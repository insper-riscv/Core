"""csr_file with base_e and no M: misa announces RV32E only."""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.csr_file import MISA, _reset, read


@cocotb.test()
async def test_misa_rve_without_m(dut):
    """The E bit (4) replaces the I bit (8); the M bit stays clear."""
    await _reset(dut)
    check_equal(await read(dut, MISA), 0x40000010)
