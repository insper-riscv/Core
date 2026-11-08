"""Testes de stage_mem: roteamento do acesso aos três subsistemas.

O endereço decide a região (FLASH, RAM interna ou SDRAM); só ela recebe
as habilitações. O acesso desalinhado que o hardware não executa gera a
exceção de endereço e nenhuma memória é acessada.
"""

import itertools

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

FLASH, RAM, SDRAM = 0x1000, 0x9000, 0x40000000
FUNCT3_LW = 0b010
OUTPUTS = (
    "flash_rden2",
    "ram_en",
    "ram_wren",
    "ram_rden",
    "ext_rden",
    "ext_wren",
    "ext_wait",
    "trap_take",
)


async def run(dut, address, fields):
    """Aplica um acesso e devolve as saídas de habilitação."""
    values = {
        "valid": 1,
        "alu_out": address,
        "ea": address,
        "funct3": FUNCT3_LW,
        "store_data": 0xCAFEBABE,
        "byte_mask": 0b1111,
        "we_ram": 0,
        "re_ram": 0,
        "en_ram": 1,
        "ext_ready": 1,
    } | fields
    for name, value in values.items():
        getattr(dut, f"i_{name}").value = value
    await Timer(1, unit="ns")
    return {name: int(getattr(dut, f"o_{name}").value) for name in OUTPUTS}


def expected(region, fields):
    """Modelo das habilitações de um acesso alinhado e válido."""
    valid = fields["valid"]
    reads, writes = fields["re_ram"] & valid, fields["we_ram"] & valid
    enabled = fields["en_ram"] & valid
    access = enabled if region == SDRAM else 0
    internal = region == RAM
    return {
        "flash_rden2": int(region == FLASH) & reads,
        "ram_en": int(internal) & enabled,
        "ram_wren": int(internal) & writes,
        "ram_rden": int(internal) & reads,
        "ext_rden": access & fields["re_ram"],
        "ext_wren": access & fields["we_ram"],
        "ext_wait": access & (1 - fields["ext_ready"]),
        "trap_take": 0,
    }


@cocotb.test()
async def test_region_routing(dut):
    """Cada região recebe só as suas habilitações."""
    for region, valid, kind, enable, ready in itertools.product(
        (FLASH, RAM, SDRAM), (0, 1), ((0, 0), (1, 0), (0, 1)), (0, 1), (0, 1)
    ):
        fields = {
            "valid": valid,
            "re_ram": kind[0],
            "we_ram": kind[1],
            "en_ram": enable,
            "ext_ready": ready,
        }
        seen = await run(dut, region, fields)
        check_equal(seen, expected(region, fields), fields)


@cocotb.test()
async def test_data_passes_through(dut):
    """Endereço, dado e máscara chegam inalterados às memórias."""
    await run(dut, RAM, {"re_ram": 1})
    check_equal(int(dut.o_ram_addr.value), RAM, "endereço da RAM")
    check_equal(int(dut.o_ram_wdata.value), 0xCAFEBABE, "dado da RAM")
    check_equal(int(dut.o_ram_byteena.value), 0b1111, "máscara da RAM")
    await run(dut, SDRAM, {"we_ram": 1, "byte_mask": 0b0110})
    check_equal(int(dut.o_ext_addr.value), SDRAM, "endereço da SDRAM")
    check_equal(int(dut.o_ext_wdata.value), 0xCAFEBABE, "dado da SDRAM")
    check_equal(int(dut.o_ext_byteena.value), 0b0110, "máscara da SDRAM")
    await run(dut, FLASH, {"re_ram": 1})
    check_equal(int(dut.o_flash_addr2.value), FLASH, "endereço da FLASH")


@cocotb.test()
async def test_misaligned_address_trap(dut):
    """O acesso desalinhado fora da RAM gera a exceção de endereço."""
    for opcode_fields, cause in (({"re_ram": 1}, 4), ({"we_ram": 1}, 6)):
        funct3 = FUNCT3_LW
        fields = opcode_fields | {"ea": FLASH + 1, "funct3": funct3}
        seen = await run(dut, FLASH + 1, fields)
        check_equal(seen["trap_take"], 1, cause)
        check_equal(int(dut.o_trap_cause.value), cause, "mcause")
        check_equal(int(dut.o_trap_tval.value), FLASH + 1, "mtval")
        for name, value in seen.items():
            if name != "trap_take":
                check_equal(value, 0, f"{name} com trap")
    seen = await run(dut, RAM + 1, {"re_ram": 1})
    check_equal(seen["trap_take"], 0, "desalinhado na RAM é executado")
    check_equal(seen["ram_rden"], 1, "o acesso segue")
