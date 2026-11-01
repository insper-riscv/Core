"""csr_file without Zicntr: the counter addresses do not exist."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

RS = 0b010
ADDRS = (0xB00, 0xB02, 0xB80, 0xB82, 0xC00, 0xC01, 0xC02, 0xC80, 0xC81, 0xC82)


@cocotb.test()
async def test_counter_addresses_are_illegal(dut):
    """Verifica counter addresses are illegal."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_commit.value = 0
    dut.i_op.value = RS
    dut.i_wdata.value = 0
    dut.i_src_zero.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    for addr in ADDRS:
        dut.i_addr.value = addr
        await Timer(1, unit="ns")
        check_equal(
            int(dut.o_illegal.value),
            1,
            f"{addr:#x} must be illegal without Zicntr",
        )
        check_equal(int(dut.o_rdata.value), 0)
