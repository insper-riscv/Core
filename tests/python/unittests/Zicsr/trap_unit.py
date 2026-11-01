"""Testes do modulo.

trap_unit: which exception the instruction in EX raises, and when it is
taken.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

OP_SYSTEM, OP_LOAD, OP_STORE, OP_ALU = (
    0b1110011,
    0b0000011,
    0b0100011,
    0b0010011,
)
CAUSE_MISALIGNED_TARGET, CAUSE_ILLEGAL, CAUSE_BREAKPOINT = 0, 2, 3
CAUSE_LOAD_MISALIGNED, CAUSE_STORE_MISALIGNED, CAUSE_ECALL = 4, 6, 11


PORTS = {
    "rd": "i_rd_idx",
    "rs1": "i_rs1_idx",
    "imm12": "i_imm12",
    "ea": "i_ea",
    "cf_taken": "i_cf_taken",
    "cf_target": "i_cf_target",
    "csr_illegal": "i_csr_illegal",
    "valid": "i_ex_valid",
    "run": "i_run",
    "illegal": "i_illegal",
}
DEFAULTS = {
    "rd": 1,
    "rs1": 2,
    "imm12": 0,
    "ea": 0,
    "cf_taken": 0,
    "cf_target": 0,
    "csr_illegal": 0,
    "valid": 1,
    "run": 1,
    "illegal": 0,
}


async def probe(dut, opcode=OP_ALU, funct3=0, **inputs):
    """Drive one instruction into the trap unit.

    Returns (take, mret_take, cause, tval). The other inputs come by
    name, as in PORTS, and the missing ones keep their DEFAULTS.
    """
    unknown = inputs.keys() - PORTS.keys()
    if unknown:
        raise TypeError(f"unknown probe inputs: {sorted(unknown)}")
    values = DEFAULTS | inputs
    dut.i_opcode.value = opcode
    dut.i_funct3.value = funct3
    for name, port in PORTS.items():
        getattr(dut, port).value = values[name]
    await Timer(1, unit="ns")
    return (
        int(dut.o_take.value),
        int(dut.o_mret_take.value),
        int(dut.o_cause.value),
        int(dut.o_tval.value),
    )


async def system(dut, imm12, funct3=0, rd=0, rs1=0, **kw):
    """Executa system."""
    return await probe(
        dut, OP_SYSTEM, funct3, rd=rd, rs1=rs1, imm12=imm12, **kw
    )


@cocotb.test()
async def test_ecall_ebreak_mret(dut):
    """Verifica ecall ebreak mret."""
    check_equal(await system(dut, 0x000), (1, 0, CAUSE_ECALL, 0))
    check_equal(await system(dut, 0x001), (1, 0, CAUSE_BREAKPOINT, 0))
    take, mret, _, _ = await system(dut, 0x302)
    check_equal((take, mret), (0, 1))


@cocotb.test()
async def test_wfi_is_a_nop(dut):
    """Verifica wfi is a nop."""
    take, mret, _, _ = await system(dut, 0x105)
    check_equal((take, mret), (0, 0))


@cocotb.test()
async def test_unsupported_system_is_illegal(dut):
    """Verifica unsupported system is illegal."""
    for imm12, funct3, rd, rs1 in [
        (0x102, 0, 0, 0),  # sret
        (0x000, 0b100, 0, 0),  # reserved funct3
        (0x000, 0, 1, 0),  # ecall with rd != x0
        (0x000, 0, 0, 1),  # ecall with rs1 != x0
        (0x120, 0, 0, 0),
    ]:  # sfence.vma
        got = await system(dut, imm12, funct3, rd, rs1)
        check_equal(
            got, (1, 0, CAUSE_ILLEGAL, 0), (imm12, funct3, rd, rs1, got)
        )


@cocotb.test()
async def test_csr_illegal_only_for_csr_instructions(dut):
    """Verifica csr illegal only for csr instructions."""
    check_equal(
        await system(dut, 0x7C0, funct3=0b001, csr_illegal=1),
        (
            1,
            0,
            CAUSE_ILLEGAL,
            0,
        ),
    )
    check_equal((await system(dut, 0x7C0, funct3=0b001, csr_illegal=0))[0], 0)
    # csr_illegal is junk for a non-CSR instruction
    check_equal((await probe(dut, OP_ALU, csr_illegal=1))[0], 0)


@cocotb.test()
async def test_load_store_alignment(dut):
    """Verifica load store alignment."""
    for funct3, ok, bad in [
        (0b010, [0, 4, 8], [1, 2, 3]),  # lw
        (0b001, [0, 2, 6], [1, 3, 7]),  # lh
        (0b101, [0, 2], [1, 3]),  # lhu
        (0b000, [0, 1, 2, 3], []),  # lb
        (0b100, [0, 1, 2, 3], []),
    ]:  # lbu
        for ea in ok:
            check_equal(
                (await probe(dut, OP_LOAD, funct3, ea=ea))[0],
                0,
                (
                    funct3,
                    ea,
                ),
            )
        for ea in bad:
            check_equal(
                await probe(dut, OP_LOAD, funct3, ea=0x1000 + ea),
                (
                    1,
                    0,
                    CAUSE_LOAD_MISALIGNED,
                    0x1000 + ea,
                ),
                (funct3, ea),
            )
    for funct3, ok, bad in [
        (0b010, [0, 4], [1, 2, 3]),
        (0b001, [0, 2], [1, 3]),
        (0b000, [0, 1, 2, 3], []),
    ]:
        for ea in ok:
            check_equal(
                (await probe(dut, OP_STORE, funct3, ea=ea))[0],
                0,
                (
                    funct3,
                    ea,
                ),
            )
        for ea in bad:
            check_equal(
                await probe(dut, OP_STORE, funct3, ea=0x2000 + ea),
                (
                    1,
                    0,
                    CAUSE_STORE_MISALIGNED,
                    0x2000 + ea,
                ),
                (funct3, ea),
            )


@cocotb.test()
async def test_misaligned_control_flow_target(dut):
    """Verifica misaligned control flow target."""
    check_equal(
        await probe(dut, cf_taken=1, cf_target=0x8002),
        (
            1,
            0,
            CAUSE_MISALIGNED_TARGET,
            0x8002,
        ),
    )
    check_equal((await probe(dut, cf_taken=1, cf_target=0x8004))[0], 0)
    # a not-taken branch with a misaligned target does not trap
    check_equal((await probe(dut, cf_taken=0, cf_target=0x8002))[0], 0)


@cocotb.test()
async def test_taken_only_when_valid_and_running(dut):
    """Verifica taken only when valid and running."""
    check_equal((await system(dut, 0x000, valid=0))[:2], (0, 0))
    check_equal((await system(dut, 0x000, run=0))[:2], (0, 0))
    check_equal((await system(dut, 0x302, valid=0))[:2], (0, 0))
    check_equal((await system(dut, 0x302, run=0))[:2], (0, 0))


@cocotb.test()
async def test_undefined_encoding_is_illegal(dut):
    """Verifica undefined encoding is illegal.

    An encoding the decoder flags traps with cause 2 and a zero mtval,
    whatever its opcode.
    """
    for opcode in (OP_ALU, OP_LOAD, OP_STORE, 0b0000000):
        check_equal(
            await probe(dut, opcode, illegal=1, ea=0x1234),
            (
                1,
                0,
                CAUSE_ILLEGAL,
                0,
            ),
        )
    # a flagged load or store with a misaligned address is still an
    # illegal instruction, with mtval zero
    check_equal(
        await probe(dut, OP_LOAD, funct3=0b010, illegal=1, ea=0x1233),
        (
            1,
            0,
            CAUSE_ILLEGAL,
            0,
        ),
    )
    check_equal(
        await probe(dut, OP_STORE, funct3=0b010, illegal=1, ea=0x1233),
        (
            1,
            0,
            CAUSE_ILLEGAL,
            0,
        ),
    )


@cocotb.test()
async def test_undefined_encoding_needs_a_running_valid_instruction(dut):
    """A bubble, or a stalled pipeline, takes nothing."""
    check_equal((await probe(dut, illegal=1, valid=0))[0], 0)
    check_equal((await probe(dut, illegal=1, run=0))[0], 0)


@cocotb.test()
async def test_misaligned_target_goes_first(dut):
    """Verifica misaligned target goes first.

    A misaligned target keeps cause 0 when the same instruction is also
    flagged.
    """
    take, _, cause, tval = await probe(
        dut, illegal=1, cf_taken=1, cf_target=0x102
    )
    check_equal((take, cause, tval), (1, CAUSE_MISALIGNED_TARGET, 0x102))


MAIN_MEMORY = [0x8000, 0x3FFFFF00, 0x40000000, 0x7FFFFFF0]
OUTSIDE_MAIN_MEMORY = [0x0, 0x1000, 0x7FF0, 0x80000000, 0xD0000000]
IN_WORD = [
    (OP_LOAD, 0b001, CAUSE_LOAD_MISALIGNED),
    (OP_LOAD, 0b101, CAUSE_LOAD_MISALIGNED),
    (OP_STORE, 0b001, CAUSE_STORE_MISALIGNED),
]
CROSSING = [
    (OP_LOAD, 0b010, 1, CAUSE_LOAD_MISALIGNED),
    (OP_LOAD, 0b010, 2, CAUSE_LOAD_MISALIGNED),
    (OP_LOAD, 0b010, 3, CAUSE_LOAD_MISALIGNED),
    (OP_LOAD, 0b001, 3, CAUSE_LOAD_MISALIGNED),
    (OP_LOAD, 0b101, 3, CAUSE_LOAD_MISALIGNED),
    (OP_STORE, 0b010, 1, CAUSE_STORE_MISALIGNED),
    (OP_STORE, 0b010, 2, CAUSE_STORE_MISALIGNED),
    (OP_STORE, 0b010, 3, CAUSE_STORE_MISALIGNED),
    (OP_STORE, 0b001, 3, CAUSE_STORE_MISALIGNED),
]


@cocotb.test()
async def test_halfword_inside_a_word_is_executed_in_main_memory(dut):
    """Verifica halfword inside a word is executed in main memory.

    LH, LHU and SH at offset 1 do not trap in the RAM or the SDRAM.
    """
    for opcode, funct3, _ in IN_WORD:
        for base in MAIN_MEMORY:
            check_equal(
                (await probe(dut, opcode, funct3, ea=base + 1))[0],
                0,
                (
                    opcode,
                    funct3,
                    hex(base),
                ),
            )


@cocotb.test()
async def test_halfword_inside_a_word_traps_outside_main_memory(dut):
    """Verifica halfword inside a word traps outside main memory.

    The flash and the peripheral window do not run a misaligned access,
    even inside a word.
    """
    for opcode, funct3, cause in IN_WORD:
        for base in OUTSIDE_MAIN_MEMORY:
            check_equal(
                await probe(dut, opcode, funct3, ea=base + 1),
                (
                    1,
                    0,
                    cause,
                    base + 1,
                ),
                (opcode, funct3, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_a_word_is_executed_in_main_memory(dut):
    """Verifica access crossing a word is executed in main memory.

    An access that spans two words of the RAM or of the SDRAM does not
    trap.
    """
    for opcode, funct3, offset, _ in CROSSING:
        for base in MAIN_MEMORY:
            check_equal(
                (await probe(dut, opcode, funct3, ea=base + offset))[0],
                0,
                (opcode, funct3, offset, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_a_word_traps_outside_main_memory(dut):
    """Verifica access crossing a word traps outside main memory.

    The flash and the peripheral window do not run an access that spans
    two words.
    """
    for opcode, funct3, offset, cause in CROSSING:
        for base in OUTSIDE_MAIN_MEMORY:
            check_equal(
                await probe(dut, opcode, funct3, ea=base + offset),
                (
                    1,
                    0,
                    cause,
                    base + offset,
                ),
                (opcode, funct3, offset, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_into_another_region_traps(dut):
    """Verifica access crossing into another region traps.

    The two words must lie in the same region: the RAM into the SDRAM,
    or the SDRAM into the peripherals, traps.
    """
    for opcode, funct3, ea, cause in [
        (OP_LOAD, 0b010, 0x3FFFFFFD, CAUSE_LOAD_MISALIGNED),
        (OP_LOAD, 0b001, 0x3FFFFFFF, CAUSE_LOAD_MISALIGNED),
        (OP_STORE, 0b010, 0x3FFFFFFE, CAUSE_STORE_MISALIGNED),
        (OP_STORE, 0b001, 0x3FFFFFFF, CAUSE_STORE_MISALIGNED),
        (OP_LOAD, 0b010, 0x7FFFFFFF, CAUSE_LOAD_MISALIGNED),
        (OP_STORE, 0b001, 0x7FFFFFFF, CAUSE_STORE_MISALIGNED),
    ]:
        check_equal(
            await probe(dut, opcode, funct3, ea=ea),
            (1, 0, cause, ea),
            (
                opcode,
                funct3,
                hex(ea),
            ),
        )
    # the last word of each region still takes an access that stays
    # inside it
    check_equal((await probe(dut, OP_LOAD, 0b010, ea=0x3FFFFFF9))[0], 0)
    check_equal((await probe(dut, OP_STORE, 0b010, ea=0x7FFFFFF9))[0], 0)
