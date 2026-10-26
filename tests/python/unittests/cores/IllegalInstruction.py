"""An instruction that RV32IM does not define traps with mcause 2 and has no effect.

The handler logs mcause of each trap and resumes after the instruction. The legal
encodings next to the illegal ones (SUB, SRA, SRAI, FENCE, MUL) must not trap.
"""

import cocotb

from tests.python.unittests.cores.harness import DONE_ADDR, RAM_BASE, run_program
from tests.python.unittests.cores.SdramStall import _b, _i, _r, _s, addi, jal_self, lui, sw

LOG_BASE = RAM_BASE + 0x100
HANDLER_WORD = 64
MTVEC, MEPC, MCAUSE = 0x305, 0x341, 0x342
SYSTEM = 0x73


def csrrw(rd, csr, rs1):
    return (csr << 20) | (rs1 << 15) | (1 << 12) | (rd << 7) | SYSTEM


def csrrs(rd, csr, rs1):
    return (csr << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | SYSTEM


MRET = 0x30200073
NOP = addi(0, 0, 0)

ILLEGAL = [
    0x00000000,                       # all zeros
    0xFFFFFFFF,                       # all ones
    0x00000001,                       # a compressed encoding
    _i(0x03, 1, 0b011, 7, 0),         # load with funct3 = 011
    _s(0b100, 7, 2, 0),               # store with funct3 = 100
    _b(0b010, 1, 2, 8),               # branch with funct3 = 010
    _i(0x67, 1, 0b001, 0, 0),         # jalr with funct3 = 001
    _i(0x13, 1, 0b001, 2, 0x400),     # slli with funct7 = 0100000
    _i(0x13, 1, 0b101, 2, 0x200),     # srli/srai with funct7 = 0010000
    _r(0x33, 1, 0b001, 2, 3, 0x20),   # sll with funct7 = 0100000
    _r(0x33, 1, 0b000, 2, 3, 0x02),   # add with funct7 = 0000010
    0x0000200F,                       # misc-mem with funct3 = 010
    0x0000007F,                       # an opcode no extension uses
]
LEGAL = [
    _r(0x33, 4, 0b000, 2, 3, 0x20),   # sub
    _r(0x33, 4, 0b101, 2, 3, 0x20),   # sra
    _i(0x13, 4, 0b101, 2, 0x401),     # srai
    0x0FF0000F,                       # fence
    _r(0x33, 4, 0b000, 2, 3, 0x01),   # mul
]


def build():
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        addi(1, 0, 0x55),             # x1 must survive every illegal instruction that writes it
        addi(2, 0, 6),
        addi(3, 0, 7),
        addi(10, 0, 0),
    ]
    for word in ILLEGAL + LEGAL:
        program += [word, addi(10, 10, 1)]
    program += [
        sw(1, 7, 0),
        sw(10, 7, 4),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    assert len(program) < HANDLER_WORD
    program += [NOP] * (HANDLER_WORD - len(program))
    program += [
        csrrs(6, MCAUSE, 0),
        sw(6, 11, 0),
        addi(11, 11, 4),
        csrrs(8, MEPC, 0),
        addi(8, 8, 4),
        csrrw(0, MEPC, 8),
        MRET,
    ]
    return program


@cocotb.test()
async def test_illegal_instructions_trap(dut):
    """Every illegal word traps once with cause 2, resumes after it, and changes nothing."""
    ram = await run_program(dut, build(), max_cycles=4000)
    for i in range(len(ILLEGAL)):
        assert ram.get(LOG_BASE + 4 * i) == 2, f"trap {i}: mcause {ram.get(LOG_BASE + 4 * i)}"
    assert LOG_BASE + 4 * len(ILLEGAL) not in ram, "a legal instruction trapped"
    assert ram[RAM_BASE] == 0x55, "an illegal instruction wrote its destination"
    assert ram[RAM_BASE + 4] == len(ILLEGAL) + len(LEGAL), "the program did not resume after each trap"
