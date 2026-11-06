"""Testes de stage_wb: seleção da palavra lida, extensão e write-back.

O estágio escolhe a palavra bruta pela região (FLASH, SDRAM ou RAM),
junta as duas palavras de um load que cruzou, estende o dado e escolhe
entre o resultado da ULA e o dado lido.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import Prng, check_equal

MASK32 = 0xFFFFFFFF
LW, LH, LHU, LB, LBU = range(5)


def sign(value, bits):
    """Estende o sinal de um valor de bits de largura."""
    return value | (MASK32 << bits) & MASK32 if value >> (bits - 1) else value


def extend(op, data, offset):
    """Modelo do extensor de loads (extender_ram)."""
    half = (data >> (8 * min(offset, 2))) & 0xFFFF
    byte = (data >> (8 * offset)) & 0xFF
    return {
        LW: data,
        LH: sign(half, 16),
        LHU: half,
        LB: sign(byte, 8),
        LBU: byte,
    }.get(op, 0)


def expected_data(fields):
    """Modelo do dado final de write-back."""
    if fields["is_flash"]:
        raw = fields["flash_data2"]
    elif fields["is_sdram"]:
        raw = fields["sdram_rdata"]
    else:
        raw = fields["ram_rdata"]
    offset = fields["alu_out"] & 3
    if fields["is_cross"]:
        pair = (raw << 32) | fields["first_word"]
        raw, offset = (pair >> (8 * offset)) & MASK32, 0
    loaded = extend(fields["ext_ram_op"], raw, offset)
    return loaded if fields["wb_sel"] else fields["alu_out"]


def random_fields(prng):
    """Sorteia um vetor de entradas do estágio."""
    fields = {
        name: prng.getrandbits(32)
        for name in (
            "alu_out",
            "flash_data2",
            "ram_rdata",
            "first_word",
            "sdram_rdata",
        )
    }
    fields["rd_idx"] = prng.getrandbits(5)
    fields["ext_ram_op"] = prng.randint(0, 7)
    for name in ("valid", "we_reg", "wb_sel", "is_flash", "is_sdram"):
        fields[name] = prng.getrandbits(1)
    fields["is_cross"] = prng.getrandbits(1)
    return fields


@cocotb.test()
async def test_write_back(dut):
    """Região, junção, extensão e seleção batem com o modelo."""
    prng = Prng(0xBACC)
    for index in range(600):
        fields = random_fields(prng)
        for name, value in fields.items():
            getattr(dut, f"i_{name}").value = value
        await Timer(1, unit="ns")
        label = (index, fields["ext_ram_op"])
        check_equal(int(dut.o_wb_data.value), expected_data(fields), label)
        check_equal(
            int(dut.o_wb_we.value), fields["we_reg"] & fields["valid"], label
        )
        check_equal(int(dut.o_wb_rd.value), fields["rd_idx"], label)
