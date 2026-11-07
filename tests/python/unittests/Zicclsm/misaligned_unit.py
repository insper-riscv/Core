"""Testes de misaligned_unit: acesso desalinhado em duas etapas.

Um load ou store que cruza a palavra é executado em duas passagens: a
primeira com o endereço original, a segunda com a palavra seguinte. A
unidade retém o pipeline na primeira, guarda a primeira palavra lida e
reparte dado e máscara de bytes entre as duas.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

LW, LH, LHU, LB, LBU = range(5)
MASK_NONE, MASK_HALF_LOW, MASK_HALF_HIGH, MASK_WORD = 0, 0b0011, 0b1100, 0xF
LAST_BYTE = 3
RAM_ADDR = 0x9000
SDRAM_ADDR = 0x40000000
IDLE = {
    "valid": 1,
    "en": 1,
    "re": 0,
    "we": 0,
    "ext_op": LW,
    "byte_mask": MASK_NONE,
    "addr": RAM_ADDR,
    "store_data": 0,
    "ready": 1,
    "advance": 1,
    "base_run": 1,
    "ram_rdata": 0,
    "ext_rdata": 0,
}


def load_crosses(op, offset):
    """Diz se o load cruza a palavra."""
    return (op == LW and offset != 0) or (
        op in (LH, LHU) and offset == LAST_BYTE
    )


def store_crosses(mask, offset):
    """Diz se o store cruza a palavra."""
    return (mask == MASK_WORD and offset != 0) or (
        mask == MASK_HALF_HIGH and offset == LAST_BYTE
    )


def store_beats(values):
    """Devolve (dado, máscara) das duas passagens de um store."""
    offset = values["addr"] & 3
    word = values["byte_mask"] == MASK_WORD
    raw = values["store_data"] if word else values["store_data"] >> 16
    mask = MASK_WORD if word else MASK_HALF_LOW
    data64 = (raw << (8 * offset)) & ((1 << 64) - 1)
    mask8 = (mask << offset) & 0xFF
    return (
        (data64 & 0xFFFFFFFF, mask8 & 0xF),
        (data64 >> 32, mask8 >> 4),
    )


async def start(dut):
    """Liga o clock e aplica reset com as entradas ociosas."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await reset(dut)


async def reset(dut):
    """Aplica reset por dois ciclos."""
    apply(dut, IDLE)
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


def apply(dut, values):
    """Aplica as entradas, completando o que falta com IDLE."""
    for name, value in (IDLE | values).items():
        getattr(dut, f"i_{name}").value = value


async def cycle(dut, values):
    """Aplica um ciclo e devolve as saídas antes da borda.

    O resultado é o dicionário de cross, stall, addr, data e mask.
    """
    apply(dut, values)
    await Timer(1, unit="ns")
    seen = {
        name: int(getattr(dut, f"o_{name}").value)
        for name in ("cross", "stall", "addr", "data", "mask")
    }
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return seen


@cocotb.test()
async def test_aligned_never_crosses(dut):
    """Acessos que não cruzam, ou sem validade, não retêm o pipeline."""
    await start(dut)
    for op in range(5):
        for offset in range(4):
            if load_crosses(op, offset):
                continue
            values = {"re": 1, "ext_op": op, "addr": RAM_ADDR + offset}
            seen = await cycle(dut, values)
            check_equal((seen["cross"], seen["stall"]), (0, 0), (op, offset))
            check_equal(seen["addr"], RAM_ADDR + offset, (op, offset))
            check_equal(seen["mask"], MASK_NONE, (op, offset))
    for gate in ("valid", "en"):
        values = {"re": 1, "addr": RAM_ADDR + 1, gate: 0}
        seen = await cycle(dut, values)
        check_equal((seen["cross"], seen["stall"]), (0, 0), gate)


@cocotb.test()
async def test_load_cross_two_passes(dut):
    """O load que cruza retém a primeira passagem e libera a segunda."""
    await start(dut)
    for op in (LW, LH, LHU):
        for offset in range(1, 4):
            if not load_crosses(op, offset):
                continue
            await reset(dut)
            values = {"re": 1, "ext_op": op, "addr": RAM_ADDR + offset}
            first = await cycle(dut, values)
            check_equal(first["cross"], 1, (op, offset))
            check_equal(first["stall"], 1, (op, offset))
            check_equal(first["addr"], RAM_ADDR + offset, (op, offset))
            second = await cycle(dut, values | {"ram_rdata": 0xA5A5A5A5})
            check_equal(second["cross"], 1, (op, offset))
            check_equal(second["stall"], 0, (op, offset))
            next_word = ((RAM_ADDR + offset) & ~3) + 4
            check_equal(second["addr"], next_word, (op, offset))
            await cycle(dut, values | {"base_run": 0})
            check_equal(int(dut.o_first_word.value), 0xA5A5A5A5, "primeira")


@cocotb.test()
async def test_waits_for_advance_and_ready(dut):
    """A primeira passagem espera o avanço e, na SDRAM, o pronto."""
    await start(dut)
    for region, wait in ((RAM_ADDR, "advance"), (SDRAM_ADDR, "ready")):
        await reset(dut)
        values = {"re": 1, "addr": region + 1}
        for _ in range(3):
            seen = await cycle(dut, values | {wait: 0})
            check_equal((seen["cross"], seen["stall"]), (1, 1), wait)
        await cycle(dut, values)
        seen = await cycle(dut, values | {"ext_rdata": 0x5A5A5A5A})
        check_equal(seen["stall"], 0, f"{wait}: segunda passagem")
        await cycle(dut, values | {"base_run": 0})
        want = 0x5A5A5A5A if region == SDRAM_ADDR else 0
        check_equal(int(dut.o_first_word.value), want, f"{wait}: região")


@cocotb.test()
async def test_second_pass_holds_until_base_run(dut):
    """A segunda passagem dura até o pipeline avançar."""
    await start(dut)
    values = {"re": 1, "addr": RAM_ADDR + 2}
    await cycle(dut, values)
    for _ in range(3):
        seen = await cycle(dut, values | {"base_run": 0})
        check_equal(seen["stall"], 0, "segunda passagem retida")
    await cycle(dut, values)
    seen = await cycle(dut, values)
    check_equal((seen["cross"], seen["stall"]), (1, 1), "nova primeira")


@cocotb.test()
async def test_store_data_and_mask(dut):
    """O store reparte dado e máscara entre as duas passagens."""
    await start(dut)
    for mask in (MASK_WORD, MASK_HALF_HIGH):
        for offset in range(4):
            if not store_crosses(mask, offset):
                continue
            await reset(dut)
            values = {
                "we": 1,
                "byte_mask": mask,
                "addr": RAM_ADDR + offset,
                "store_data": 0x89ABCDEF,
            }
            beats = store_beats(values)
            first = await cycle(dut, values)
            second = await cycle(dut, values)
            check_equal((first["data"], first["mask"]), beats[0], offset)
            check_equal((second["data"], second["mask"]), beats[1], offset)
            check_equal(first["stall"] & (1 - second["stall"]), 1, offset)
