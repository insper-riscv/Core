"""Testes de reg_ex_mem com HAS_ACCESS_FAULTS e STRICT_PERIPH falso.

Com os periféricos não estritos todo slot da janela de periféricos
aceita leitura e escrita, ocupado ou não; o resto do mapa segue como
em reg_ex_mem_faults.
"""

import cocotb

from tests.python.unittests.common.reg_ex_mem_faults import (
    CASES,
    check_cases,
)

PERIPH_BASE = 0x80000000
LOOSE = [
    (address, 1, 1) if address >= PERIPH_BASE else (address, rd, wr)
    for address, rd, wr in CASES
]


@cocotb.test()
async def test_every_slot_accepts_access(dut):
    """Verifica que o slot vazio aceita leitura e escrita."""
    await check_cases(dut, LOOSE)
