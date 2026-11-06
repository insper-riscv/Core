"""Testes de stage_id: decodificação, banco de registradores e hazards.

Cobre o estágio ID sem extensões: campos e imediato de cada formato, os
controles de escrita e leitura, o banco de registradores, a detecção
dos casamentos de forwarding, o load-use e a bolha do estágio.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng, check_equal

OP_LUI, OP_LOAD, OP_STORE = 0b0110111, 0b0000011, 0b0100011
OP_OP_IMM, OP_OP, OP_BRANCH, OP_JAL = (
    0b0010011,
    0b0110011,
    0b1100011,
    0b1101111,
)
IDLE = {
    "ifid_valid": 1,
    "wb_we": 0,
    "wb_rd": 0,
    "wb_data": 0,
    "mem_rd": 0,
    "mem_we_reg": 0,
    "memwb_rd": 0,
    "memwb_we_reg": 0,
    "mem_re_ram": 0,
    "ex_rd": 0,
    "ex_we_reg": 0,
    "ex_re_ram": 0,
    "pipe_stall": 0,
}
CONTROLS = ("we_reg", "we_ram", "re_ram", "en_ram")


def sext(value, width):
    """Estende o sinal de um valor de width bits."""
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


def field(value, high, low):
    """Extrai os bits [high:low] de um valor."""
    return (value >> low) & ((1 << (high - low + 1)) - 1)


def encode_i(opcode, fields):
    """Codifica o formato I (rd, funct3, rs1, imm12)."""
    rd, funct3, rs1, imm = fields
    return (imm & 0xFFF) << 20 | rs1 << 15 | funct3 << 12 | rd << 7 | opcode


def encode_r(opcode, fields):
    """Codifica o formato R (rd, funct3, rs1, rs2)."""
    rd, funct3, rs1, rs2 = fields
    return rs2 << 20 | rs1 << 15 | funct3 << 12 | rd << 7 | opcode


def encode_s(funct3, rs1, rs2, imm):
    """Codifica o formato S (store)."""
    return (
        field(imm, 11, 5) << 25
        | rs2 << 20
        | rs1 << 15
        | funct3 << 12
        | field(imm, 4, 0) << 7
        | OP_STORE
    )


def encode_b(funct3, rs1, rs2, imm):
    """Codifica o formato B (desvio), com imm par."""
    return (
        field(imm, 12, 12) << 31
        | field(imm, 10, 5) << 25
        | rs2 << 20
        | rs1 << 15
        | funct3 << 12
        | field(imm, 4, 1) << 8
        | field(imm, 11, 11) << 7
        | OP_BRANCH
    )


def encode_j(rd, imm):
    """Codifica o formato J (JAL), com imm par."""
    return (
        field(imm, 20, 20) << 31
        | field(imm, 10, 1) << 21
        | field(imm, 11, 11) << 20
        | field(imm, 19, 12) << 12
        | rd << 7
        | OP_JAL
    )


async def start(dut):
    """Liga o clock e aplica reset."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await apply(dut, 0, {"rst": 1})
    await RisingEdge(dut.i_clk)
    await apply(dut, 0, {})


async def apply(dut, instr, values):
    """Aplica instrução e entradas (sobre IDLE) e propaga."""
    dut.i_rst.value = 0
    dut.i_instr.value = instr
    for name, value in (IDLE | values).items():
        getattr(dut, f"i_{name}").value = value
    await Timer(1, unit="ns")


def read(dut, names):
    """Lê as saídas pedidas como inteiros."""
    return {name: int(getattr(dut, f"o_{name}").value) for name in names}


@cocotb.test()
async def test_decode_formats(dut):
    """Índices, imediato e controles de cada formato de instrução."""
    await start(dut)
    prng = Prng(0x1D)
    for index in range(100):
        rd, rs1, rs2 = (prng.getrandbits(5) for _ in range(3))
        imm = prng.getrandbits(32)
        cases = (
            (
                encode_i(OP_OP_IMM, (rd, 0, rs1, imm)),
                sext(imm, 12),
                (1, 0, 0, 0),
                1,
            ),
            (
                encode_i(OP_LOAD, (rd, 2, rs1, imm)),
                sext(imm, 12),
                (1, 0, 1, 1),
                1,
            ),
            (encode_s(2, rs1, rs2, imm), sext(imm, 12), (0, 1, 0, 1), 1),
            (encode_b(0, rs1, rs2, imm), sext(imm, 13) & ~1, (0, 0, 0, 0), 0),
            (
                OP_LUI | rd << 7 | (imm & 0xFFFFF000),
                imm & 0xFFFFF000,
                (1, 0, 0, 0),
                1,
            ),
            (encode_j(rd, imm), sext(imm, 21) & ~1, (1, 0, 0, 0), 1),
            (encode_r(OP_OP, (rd, 0, rs1, rs2)), None, (1, 0, 0, 0), 0),
        )
        for instr, want_imm, controls, sel_imm in cases:
            await apply(dut, instr, {})
            seen = read(
                dut, ("rs1_idx", "rs2_idx", "rd_idx", "imm", "illegal")
            )
            label = (index, hex(instr))
            check_equal(
                (seen["rs1_idx"], seen["rs2_idx"], seen["rd_idx"]),
                (
                    field(instr, 19, 15),
                    field(instr, 24, 20),
                    field(instr, 11, 7),
                ),
                label,
            )
            check_equal(seen["illegal"], 0, label)
            if want_imm is not None:
                check_equal(seen["imm"], want_imm & 0xFFFFFFFF, label)
            check_equal(tuple(read(dut, CONTROLS).values()), controls, label)
            check_equal(read(dut, ("opcode",))["opcode"], instr & 0x7F, label)
            check_equal(
                read(dut, ("sel_rs2_imm",))["sel_rs2_imm"], sel_imm, label
            )


@cocotb.test()
async def test_illegal_instructions(dut):
    """Instrução sem decodificação, e MUL sem M, são ilegais."""
    await start(dut)
    for instr in (
        0x00000000,
        0xFFFFFFFF,
        encode_r(OP_OP, (1, 0, 2, 3)) | (1 << 25),
    ):
        await apply(dut, instr, {})
        check_equal(read(dut, ("illegal",))["illegal"], 1, hex(instr))
    await apply(dut, encode_r(OP_OP, (1, 0, 2, 3)), {})
    check_equal(
        read(dut, ("illegal", "is_muldiv")),
        {"illegal": 0, "is_muldiv": 0},
        "ADD",
    )


@cocotb.test()
async def test_register_file(dut):
    """O banco guarda o write-back e o x0 lê sempre zero."""
    await start(dut)
    for register, data in ((5, 0x12345678), (7, 0x9ABCDEF0), (0, 0xFFFFFFFF)):
        await apply(dut, 0, {"wb_we": 1, "wb_rd": register, "wb_data": data})
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    await apply(dut, encode_r(OP_OP, (1, 0, 5, 7)), {})
    seen = read(dut, ("rs1_val", "rs2_val"))
    check_equal(
        (seen["rs1_val"], seen["rs2_val"]), (0x12345678, 0x9ABCDEF0), "x5 e x7"
    )
    await apply(dut, encode_r(OP_OP, (1, 0, 0, 7)), {})
    check_equal(read(dut, ("rs1_val",))["rs1_val"], 0, "x0")


@cocotb.test()
async def test_forwarding_matches(dut):
    """Os casamentos de EX, MEM e WB com rs1 e rs2 (x0 nunca casa)."""
    await start(dut)
    instr = encode_r(OP_OP, (1, 0, 5, 7))
    cases = (
        ({"ex_rd": 5, "ex_we_reg": 1}, (0b001, 0b000)),
        ({"mem_rd": 7, "mem_we_reg": 1}, (0b000, 0b010)),
        ({"memwb_rd": 5, "memwb_we_reg": 1}, (0b100, 0b000)),
        ({"ex_rd": 5, "ex_we_reg": 0}, (0b000, 0b000)),
        (
            {"ex_rd": 5, "ex_we_reg": 1, "mem_rd": 5, "mem_we_reg": 1},
            (0b011, 0b000),
        ),
    )
    for values, (match1, match2) in cases:
        await apply(dut, instr, values)
        seen = read(dut, ("fwd_match_rs1", "fwd_match_rs2"))
        check_equal(
            (seen["fwd_match_rs1"], seen["fwd_match_rs2"]),
            (match1, match2),
            values,
        )
    await apply(
        dut, encode_r(OP_OP, (1, 0, 0, 7)), {"ex_rd": 0, "ex_we_reg": 1}
    )
    check_equal(read(dut, ("fwd_match_rs1",))["fwd_match_rs1"], 0, "x0")


@cocotb.test()
async def test_load_use_hazard_bubble(dut):
    """Load-use, stall externo e IF/ID inválido seguram o estágio."""
    await start(dut)
    instr = encode_r(OP_OP, (1, 0, 5, 7))
    free = {"ex_rd": 9, "ex_re_ram": 1}
    cases = (
        ({}, (1, 1, 1)),
        (free, (1, 1, 1)),
        ({"ex_rd": 5, "ex_re_ram": 1}, (0, 0, 0)),
        ({"ex_rd": 7, "ex_re_ram": 1}, (0, 0, 0)),
        ({"mem_rd": 7, "mem_re_ram": 1}, (0, 0, 0)),
        ({"ex_rd": 5, "ex_re_ram": 0}, (1, 1, 1)),
        ({"pipe_stall": 1}, (0, 0, 0)),
        ({"ifid_valid": 0}, (1, 1, 0)),
    )
    for values, (pc_we, ifid_we, valid) in cases:
        await apply(dut, instr, values)
        seen = read(dut, ("pc_we", "ifid_we", "idex_valid"))
        check_equal(
            (seen["pc_we"], seen["ifid_we"], seen["idex_valid"]),
            (pc_we, ifid_we, valid),
            values,
        )
        if not pc_we:
            check_equal(
                tuple(read(dut, CONTROLS).values()), (0, 0, 0, 0), values
            )
