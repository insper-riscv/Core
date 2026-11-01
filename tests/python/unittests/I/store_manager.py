"""Testes de StoreManager."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

# Constantes
OPCODE_STORE = 0b0100011
FUNCT3_SW = 0b010
FUNCT3_SH = 0b001
FUNCT3_SB = 0b000


async def apply_and_check(dut, access, rs2, expected):
    """Executa apply and check."""
    funct3, ea = access
    exp_data, exp_mask = expected
    dut.i_opcode.value = OPCODE_STORE
    dut.i_funct3.value = funct3
    dut.i_byte_offset.value = ea
    dut.i_rs2_data.value = rs2

    await Timer(1, units="ns")

    got_data = int(dut.o_data.value)
    got_mask = int(dut.o_byte_mask.value)

    check_equal(
        got_data,
        exp_data,
        f"funct3={funct3:03b}, EA={ea:02b}: esperado data=0x{exp_data:08X}, "
        f"obtido 0x{got_data:08X}",
    )
    check_equal(
        got_mask,
        exp_mask,
        f"funct3={funct3:03b}, EA={ea:02b}: esperado mask={exp_mask:04b}, "
        f"obtido {got_mask:04b}",
    )


@cocotb.test()
async def sw(dut):
    """Testa Store Word (SW)."""
    rs2 = 0xAABBCCDD
    await apply_and_check(dut, (FUNCT3_SW, 0b00), rs2, (rs2, 0b1111))


@cocotb.test()
async def sh(dut):
    """Testa Store Halfword (SH)."""
    rs2 = 0x0000BEEF

    # EA[1]=0 → bytes 0 e 1
    await apply_and_check(dut, (FUNCT3_SH, 0b00), rs2, (0x0000BEEF, 0b0011))

    # EA[1]=1 → bytes 2 e 3
    await apply_and_check(dut, (FUNCT3_SH, 0b10), rs2, (0xBEEF0000, 0b1100))


@cocotb.test()
async def sb(dut):
    """Testa Store Byte (SB)."""
    rs2 = 0x000000AA

    # EA=00 → byte0
    await apply_and_check(dut, (FUNCT3_SB, 0b00), rs2, (0x000000AA, 0b0001))

    # EA=01 → byte1
    await apply_and_check(dut, (FUNCT3_SB, 0b01), rs2, (0x0000AA00, 0b0010))

    # EA=10 → byte2
    await apply_and_check(dut, (FUNCT3_SB, 0b10), rs2, (0x00AA0000, 0b0100))

    # EA=11 → byte3
    await apply_and_check(dut, (FUNCT3_SB, 0b11), rs2, (0xAA000000, 0b1000))


@cocotb.test()
async def invalid_opcode(dut):
    """Testa opcode inválido."""
    dut.i_opcode.value = 0b0000000
    dut.i_funct3.value = 0b111
    dut.i_byte_offset.value = 0b00
    dut.i_rs2_data.value = 0x12345678

    await Timer(1, units="ns")

    check_equal(int(dut.o_data.value), 0)
    check_equal(int(dut.o_byte_mask.value), 0)
