"""Testes do modulo.

Com a Zicond ligada, czero.eqz e czero.nez executam no pipeline.

O programa cobre rs2 igual a zero e diferente de zero (inclusive so o
bit mais alto), rd igual a rs1, rd igual a x0, rs1 igual a x0, rs1 e
rs2 no mesmo registrador, o adiantamento do operando rs2 e do
resultado, e confere cada resultado contra o modelo do manual.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.sdram_stall import (
    _r,
    add,
    addi,
    jal_self,
    lui,
    sw,
)

FUNCT7_ZICOND = 0x07
EQZ, NEZ = 0b101, 0b111
MASK32 = 0xFFFFFFFF
SIGN_BIT_12 = 0x800
VALUE = 0xDEADBEEF
NOP = addi(0, 0, 0)


def czero(funct3, rd, rs1, rs2):
    """Codifica czero.eqz (funct3 101) ou czero.nez (funct3 111)."""
    return _r(rd, funct3, rs1, rs2, FUNCT7_ZICOND)


def load_value(rd, value):
    """Carrega uma constante de 32 bits em rd com lui e addi."""
    low = value & 0xFFF
    if low >= SIGN_BIT_12:
        low -= 1 << 12
    return [
        lui(rd, ((value - low) >> 12) & 0xFFFFF),
        addi(rd, rd, low),
    ]


def model(funct3, rs1, rs2):
    """Modelo da secao 10.1.1 do manual: zero ou rs1."""
    if funct3 == EQZ:
        return 0 if rs2 == 0 else rs1
    return 0 if rs2 != 0 else rs1


# Origens: x1 = VALUE, x2 = 0, x5 = 1, x6 = so o bit mais alto.
SOURCES = {1: VALUE, 2: 0, 5: 1, 6: 0x80000000}
# Cada caso e (funct3, rd, rs1, rs2); o resultado vai para a palavra k.
CASES = [
    (EQZ, 10, 1, 2),
    (EQZ, 11, 1, 5),
    (EQZ, 12, 1, 6),
    (NEZ, 13, 1, 2),
    (NEZ, 14, 1, 5),
    (NEZ, 15, 1, 6),
    (EQZ, 16, 1, 1),  # rs1 e rs2 no mesmo registrador, diferente de zero
    (NEZ, 17, 1, 1),
    (EQZ, 18, 0, 5),  # rs1 = x0
    (NEZ, 19, 0, 2),
    (NEZ, 20, 0, 5),
    (EQZ, 21, 0, 2),
]


def build():
    """Monta o programa de teste."""
    program = [NOP, lui(7, RAM_BASE >> 12)]
    for reg, value in SOURCES.items():
        if value:
            program += load_value(reg, value)
    for k, (funct3, rd, rs1, rs2) in enumerate(CASES):
        program += [czero(funct3, rd, rs1, rs2), sw(rd, 7, 4 * k)]
    base = len(CASES)
    # rd igual a rs1: o valor antigo e lido antes da escrita.
    program += load_value(22, VALUE) + load_value(23, VALUE)
    program += [
        czero(EQZ, 22, 22, 2),
        sw(22, 7, 4 * base),
        czero(NEZ, 23, 23, 2),
        sw(23, 7, 4 * (base + 1)),
        # rd igual a x0: a escrita e descartada.
        czero(NEZ, 0, 1, 2),
        czero(EQZ, 0, 1, 5),
        sw(0, 7, 4 * (base + 2)),
        # rs2 vem da instrucao anterior (adiantamento do operando).
        addi(24, 0, 0),
        czero(NEZ, 25, 1, 24),
        sw(25, 7, 4 * (base + 3)),
        addi(24, 0, 3),
        czero(NEZ, 26, 1, 24),
        sw(26, 7, 4 * (base + 4)),
        # o resultado e usado na instrucao seguinte (adiantamento).
        czero(EQZ, 27, 1, 5),
        add(28, 27, 27),
        sw(28, 7, 4 * (base + 5)),
        czero(EQZ, 29, 1, 2),
        add(30, 29, 5),
        sw(30, 7, 4 * (base + 6)),
        addi(31, 0, 1),
        sw(31, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    return program


def expected():
    """Palavras esperadas na RAM, na ordem da gravacao."""
    values = dict(SOURCES)
    values[0] = 0
    words = [model(f3, values[rs1], values[rs2]) for f3, _, rs1, rs2 in CASES]
    words += [
        model(EQZ, VALUE, 0),
        model(NEZ, VALUE, 0),
        0,
        model(NEZ, VALUE, 0),
        model(NEZ, VALUE, 3),
        (2 * model(EQZ, VALUE, 1)) & MASK32,
        (model(EQZ, VALUE, 0) + 1) & MASK32,
    ]
    return words


@cocotb.test()
async def test_zicond_executes(dut):
    """Verifica que as duas instrucoes calculam o resultado do manual.

    Cada palavra gravada na RAM coincide com o modelo de referencia.
    """
    ram = await run_program(dut, build(), max_cycles=4000)
    for k, want in enumerate(expected()):
        got = ram[RAM_BASE + 4 * k]
        check_equal(got, want, f"palavra {k}: {got:#x} != {want:#x}")
