"""Testes de reg_ex_mem com a FLASH no barramento e falhas de acesso.

A FLASH de 4 KiB a 32 KiB faz parte da memória principal, mas só
aceita leitura: o store nela é a falha da causa 7, e o acesso
desalinhado nela é executado pelo hardware como em qualquer outra
região da memória principal.
"""

import cocotb

from tests.python.unittests.common.reg_ex_mem_addr_ok import Map, check_map

WORDS = [
    0x00000100,
    0x00000FFC,
    0x00001000,
    0x00007FFC,
    0x00008000,
    0x3FFFFFFC,
    0x40000000,
    0xFFFFFFFC,
]
LAST_WORDS = {0x0FFC, 0x7FFC, 0x3FFFFFFC, 0xFFFFFFFC}


@cocotb.test()
async def test_address_exception_with_the_flash_on_the_bus(dut):
    """Confere a exceção de endereço com a FLASH só de leitura."""
    await check_map(dut, Map(0x1000, 0x8000, LAST_WORDS, WORDS, ((0x1000, 0x8000),)))
