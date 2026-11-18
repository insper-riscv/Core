"""Testes de reg_ex_mem com Zicsr, Zicclsm e falhas de acesso.

A exceção de endereço do load ou store é decidida em MEM por três bits
registrados em EX (do funct3, dos controles e dos dois bits baixos do
endereço) e pela região registrada. O resultado tem de ser o do
trap_unit: o desalinhamento que o hardware não executa (causas 4 e 6)
e o store em região só de leitura (causa 7).

Mapa do teste: BOOT_MEMORY em [0, 4 KiB), FLASH em [4 KiB, 6 KiB),
RAM em [8 KiB, 16 KiB) e todo o resto pela porta externa. A memória
principal começa em 6 KiB e é a única que aceita escrita.
"""

from typing import NamedTuple

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

FUNCT3_HALF = (0b001, 0b101)
FUNCT3_WORD = 0b010
FUNCT3_SH = 0b001
OFFSET_1 = 0b01
OFFSET_3 = 0b11
# Última palavra de cada região de caminho próprio.
LAST_WORDS = {0x0FFC, 0x17FC, 0x1FFC, 0x3FFC, 0xFFFFFFFC}
# Uma palavra em cada região e em cada fronteira.
WORDS = [
    0x00000100,
    0x00000FFC,
    0x00001000,
    0x000017FC,
    0x00001800,
    0x00001FFC,
    0x00002000,
    0x00003FFC,
    0x00004000,
    0x40000000,
    0xFFFFFFFC,
]


class Map(NamedTuple):
    """Mapa de memória do teste."""

    main_base: int
    write_base: int
    last_words: set[int]
    words: list[int]
    bus_mem: tuple[tuple[int, int], ...] = ()


def is_unaligned(address, funct3, controls):
    """Diz se o load ou store é desalinhado."""
    low = address & OFFSET_3
    re_ram, we_ram = controls
    is_load, is_store = bool(re_ram), bool(we_ram and not re_ram)
    word = funct3 == FUNCT3_WORD and low != 0
    half_load = funct3 in FUNCT3_HALF and bool(low & 1)
    half_store = funct3 == FUNCT3_SH and bool(low & 1)
    return (
        ((is_load or is_store) and word)
        or (is_load and half_load)
        or (is_store and half_store)
    )


def is_executed(address, funct3, memory):
    """Diz se o hardware executa o acesso desalinhado."""
    low = address & OFFSET_3
    word = funct3 == FUNCT3_WORD
    half = funct3 in FUNCT3_HALF
    crossing = (word and low != 0) or (half and low == OFFSET_3)
    first_byte = address & ~OFFSET_3
    last = first_byte in memory.last_words
    in_word = half and low == OFFSET_1
    return address >= memory.main_base and (in_word or (not last and crossing))


def expected_ok(address, funct3, controls, memory):
    """Modelo da decisão de endereço de um load ou store em MEM."""
    is_store = bool(controls[1] and not controls[0])
    executed = is_executed(address, funct3, memory)
    misaligned = is_unaligned(address, funct3, controls) and not executed
    refused = is_store and address < memory.write_base and not misaligned
    return int(not (misaligned or refused))


def registered_ok(dut):
    """Compõe a exceção de endereço dos bits registrados e da região."""
    main = int(dut.o_in_main.value)
    same = int(dut.o_same_region.value)
    at_last = main and not same and int(dut.o_ea_xlast.value)
    outside = not main and int(dut.o_ea_unal.value)
    read_only = not int(dut.o_ok_wr.value) and int(dut.o_ea_stf.value)
    return int(not (at_last or outside or read_only))


def expected_bus_mem(address, memory):
    """Modelo da classificação de memória do barramento."""
    # as janelas da FLASH e da RAM que estão no barramento
    return int(any(low <= address < high for low, high in memory.bus_mem))


async def apply(dut, address, funct3, controls):
    """Aplica um acesso e espera o registrador capturá-lo."""
    dut.i_ea.value = address
    dut.i_funct3.value = funct3
    dut.i_re_ram.value, dut.i_we_ram.value = controls
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def check_map(dut, memory):
    """Confere os bits registrados contra o modelo do trap_unit."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 0
    dut.i_en.value = 1
    dut.i_flush.value = 0
    await RisingEdge(dut.i_clk)
    for word in memory.words:
        for low in range(4):
            for funct3 in range(8):
                for controls in ((0, 0), (1, 0), (0, 1)):
                    address = word + low
                    await apply(dut, address, funct3, controls)
                    check_equal(
                        registered_ok(dut),
                        expected_ok(address, funct3, controls, memory),
                        (hex(address), funct3, controls),
                    )
                    check_equal(
                        int(dut.o_is_bus_mem.value),
                        expected_bus_mem(address, memory),
                        (hex(address), "bus_mem"),
                    )
    await apply(dut, OFFSET_3, FUNCT3_WORD, (1, 0))
    dut.i_flush.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_equal(registered_ok(dut), 1, "a bolha não gera exceção")
    check_equal(
        int(dut.o_is_bus_mem.value), 0, "a bolha não é acesso ao barramento"
    )


@cocotb.test()
async def test_address_exception_matches_the_trap_unit(dut):
    """Confere a exceção de endereço com a FLASH pela porta direta."""
    await check_map(dut, Map(0x1800, 0x1800, LAST_WORDS, WORDS))
