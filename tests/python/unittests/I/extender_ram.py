"""Testes de ExtenderRAM."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

HALF_SIGN = 0x8000
BYTE_SIGN = 0x80

# Constantes iguais às do seu pacote VHDL rv32i_ctrl_consts
OPEXRAM_LW = 0b000
OPEXRAM_LH = 0b001
OPEXRAM_LHU = 0b010
OPEXRAM_LB = 0b011
OPEXRAM_LBU = 0b100


async def apply_and_check(dut, select, sig_in, expected, desc=""):
    """Executa apply and check."""
    op_ex_ram, byte_offset = select
    dut.i_data.value = sig_in
    dut.i_op.value = op_ex_ram
    dut.i_byte_offset.value = byte_offset

    await Timer(1, units="ns")

    got = (
        int(dut.o_data.value.signed_integer)
        if op_ex_ram in (OPEXRAM_LH, OPEXRAM_LB)
        else int(dut.o_data.value)
    )

    check_equal(
        got,
        expected,
        f"{desc} falhou: esperado {expected:#010x}, obtido {got:#010x}",
    )


@cocotb.test()
async def lw(dut):
    """Testa LW: deve retornar a word inteira."""
    sig_in = 0xAABBCCDD
    await apply_and_check(dut, (OPEXRAM_LW, 0b00), sig_in, 0xAABBCCDD, "LW")


@cocotb.test()
async def lh_lhu(dut):
    """Testa LH e LHU com EA=0 e EA=2."""
    sig_in = 0xAABBCCDD  # b0=DD, b1=CC, b2=BB, b3=AA

    # LH EA=0 -> 0xCCDD sign-extend
    half0 = 0xCCDD
    signed_half0 = half0 if half0 < HALF_SIGN else half0 - 0x10000
    await apply_and_check(
        dut, (OPEXRAM_LH, 0b00), sig_in, signed_half0, "LH EA=0"
    )

    # LH EA=2 -> 0xAABB sign-extend
    half2 = 0xAABB
    signed_half2 = half2 if half2 < HALF_SIGN else half2 - 0x10000
    await apply_and_check(
        dut, (OPEXRAM_LH, 0b10), sig_in, signed_half2, "LH EA=2"
    )

    # LHU EA=0 -> 0x0000CCDD
    await apply_and_check(
        dut, (OPEXRAM_LHU, 0b00), sig_in, 0x0000CCDD, "LHU EA=0"
    )

    # LHU EA=2 -> 0x0000AABB
    await apply_and_check(
        dut, (OPEXRAM_LHU, 0b10), sig_in, 0x0000AABB, "LHU EA=2"
    )


@cocotb.test()
async def lb_lbu(dut):
    """Testa LB e LBU com todos os valores de EA."""
    sig_in = 0xAABBCCDD  # b0=DD, b1=CC, b2=BB, b3=AA

    # LB com sign-extend
    for ea, exp_byte in [
        (0b00, 0xDD),
        (0b01, 0xCC),
        (0b10, 0xBB),
        (0b11, 0xAA),
    ]:
        signed_val = exp_byte if exp_byte < BYTE_SIGN else exp_byte - 0x100
        await apply_and_check(
            dut, (OPEXRAM_LB, ea), sig_in, signed_val, f"LB EA={ea}"
        )

    # LBU com zero-extend
    for ea, exp_byte in [
        (0b00, 0xDD),
        (0b01, 0xCC),
        (0b10, 0xBB),
        (0b11, 0xAA),
    ]:
        await apply_and_check(
            dut, (OPEXRAM_LBU, ea), sig_in, exp_byte, f"LBU EA={ea}"
        )
