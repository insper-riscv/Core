"""csr_file with has_m = false: misa announces RV32I only."""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.csr_file import MISA, _reset, read


@cocotb.test()
async def test_misa_without_m(dut):
    """The M bit (12) is clear and the MXL and I bits stay."""
    await _reset(dut)
    check_equal(await read(dut, MISA), 0x40000100)
