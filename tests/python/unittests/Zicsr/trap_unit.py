"""Testes do modulo.

trap_unit: which exception the instruction in EX raises, and when it is
taken.
"""

import cocotb
from cocotb.triggers import Timer

OP_SYSTEM, OP_LOAD, OP_STORE, OP_ALU = (
    0b1110011,
    0b0000011,
    0b0100011,
    0b0010011,
)
CAUSE_MISALIGNED_TARGET, CAUSE_ILLEGAL, CAUSE_BREAKPOINT = 0, 2, 3
CAUSE_LOAD_MISALIGNED, CAUSE_STORE_MISALIGNED, CAUSE_ECALL = 4, 6, 11


async def probe(
    dut,
    opcode=OP_ALU,
    funct3=0,
    rd=1,
    rs1=2,
    imm12=0,
    ea=0,
    cf_taken=0,
    cf_target=0,
    csr_illegal=0,
    valid=1,
    run=1,
    illegal=0,
):
    """Executa probe."""
    dut.i_ex_valid.value = valid
    dut.i_run.value = run
    dut.i_opcode.value = opcode
    dut.i_funct3.value = funct3
    dut.i_rd_idx.value = rd
    dut.i_rs1_idx.value = rs1
    dut.i_imm12.value = imm12
    dut.i_ea.value = ea
    dut.i_cf_taken.value = cf_taken
    dut.i_cf_target.value = cf_target
    dut.i_csr_illegal.value = csr_illegal
    dut.i_illegal.value = illegal
    await Timer(1, unit="ns")
    return (
        int(dut.o_take.value),
        int(dut.o_mret_take.value),
        int(dut.o_cause.value),
        int(dut.o_tval.value),
    )


async def system(dut, imm12, funct3=0, rd=0, rs1=0, **kw):
    """Executa system."""
    return await probe(dut, OP_SYSTEM, funct3, rd, rs1, imm12, **kw)


@cocotb.test()
async def test_ecall_ebreak_mret(dut):
    """Verifica ecall ebreak mret."""
    assert await system(dut, 0x000) == (1, 0, CAUSE_ECALL, 0)
    assert await system(dut, 0x001) == (1, 0, CAUSE_BREAKPOINT, 0)
    take, mret, _, _ = await system(dut, 0x302)
    assert (take, mret) == (0, 1)


@cocotb.test()
async def test_wfi_is_a_nop(dut):
    """Verifica wfi is a nop."""
    take, mret, _, _ = await system(dut, 0x105)
    assert (take, mret) == (0, 0)


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
        assert got == (1, 0, CAUSE_ILLEGAL, 0), (imm12, funct3, rd, rs1, got)


@cocotb.test()
async def test_csr_illegal_only_for_csr_instructions(dut):
    """Verifica csr illegal only for csr instructions."""
    assert await system(dut, 0x7C0, funct3=0b001, csr_illegal=1) == (
        1,
        0,
        CAUSE_ILLEGAL,
        0,
    )
    assert (await system(dut, 0x7C0, funct3=0b001, csr_illegal=0))[0] == 0
    # csr_illegal is junk for a non-CSR instruction
    assert (await probe(dut, OP_ALU, csr_illegal=1))[0] == 0


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
            assert (await probe(dut, OP_LOAD, funct3, ea=ea))[0] == 0, (
                funct3,
                ea,
            )
        for ea in bad:
            assert await probe(dut, OP_LOAD, funct3, ea=0x1000 + ea) == (
                1,
                0,
                CAUSE_LOAD_MISALIGNED,
                0x1000 + ea,
            ), (funct3, ea)
    for funct3, ok, bad in [
        (0b010, [0, 4], [1, 2, 3]),
        (0b001, [0, 2], [1, 3]),
        (0b000, [0, 1, 2, 3], []),
    ]:
        for ea in ok:
            assert (await probe(dut, OP_STORE, funct3, ea=ea))[0] == 0, (
                funct3,
                ea,
            )
        for ea in bad:
            assert await probe(dut, OP_STORE, funct3, ea=0x2000 + ea) == (
                1,
                0,
                CAUSE_STORE_MISALIGNED,
                0x2000 + ea,
            ), (funct3, ea)


@cocotb.test()
async def test_misaligned_control_flow_target(dut):
    """Verifica misaligned control flow target."""
    assert await probe(dut, cf_taken=1, cf_target=0x8002) == (
        1,
        0,
        CAUSE_MISALIGNED_TARGET,
        0x8002,
    )
    assert (await probe(dut, cf_taken=1, cf_target=0x8004))[0] == 0
    # a not-taken branch with a misaligned target does not trap
    assert (await probe(dut, cf_taken=0, cf_target=0x8002))[0] == 0


@cocotb.test()
async def test_taken_only_when_valid_and_running(dut):
    """Verifica taken only when valid and running."""
    assert (await system(dut, 0x000, valid=0))[:2] == (0, 0)
    assert (await system(dut, 0x000, run=0))[:2] == (0, 0)
    assert (await system(dut, 0x302, valid=0))[:2] == (0, 0)
    assert (await system(dut, 0x302, run=0))[:2] == (0, 0)


@cocotb.test()
async def test_undefined_encoding_is_illegal(dut):
    """Verifica undefined encoding is illegal.

    An encoding the decoder flags traps with cause 2 and a zero mtval,
    whatever its opcode.
    """
    for opcode in (OP_ALU, OP_LOAD, OP_STORE, 0b0000000):
        assert await probe(dut, opcode, illegal=1, ea=0x1234) == (
            1,
            0,
            CAUSE_ILLEGAL,
            0,
        )
    # a flagged load or store with a misaligned address is still an
    # illegal instruction, with mtval zero
    assert await probe(dut, OP_LOAD, funct3=0b010, illegal=1, ea=0x1233) == (
        1,
        0,
        CAUSE_ILLEGAL,
        0,
    )
    assert await probe(dut, OP_STORE, funct3=0b010, illegal=1, ea=0x1233) == (
        1,
        0,
        CAUSE_ILLEGAL,
        0,
    )


@cocotb.test()
async def test_undefined_encoding_needs_a_running_valid_instruction(dut):
    """A bubble, or a stalled pipeline, takes nothing."""
    assert (await probe(dut, illegal=1, valid=0))[0] == 0
    assert (await probe(dut, illegal=1, run=0))[0] == 0


@cocotb.test()
async def test_misaligned_target_goes_first(dut):
    """Verifica misaligned target goes first.

    A misaligned target keeps cause 0 when the same instruction is also
    flagged.
    """
    take, _, cause, tval = await probe(
        dut, illegal=1, cf_taken=1, cf_target=0x102
    )
    assert (take, cause, tval) == (1, CAUSE_MISALIGNED_TARGET, 0x102)


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
            assert (await probe(dut, opcode, funct3, ea=base + 1))[0] == 0, (
                opcode,
                funct3,
                hex(base),
            )


@cocotb.test()
async def test_halfword_inside_a_word_traps_outside_main_memory(dut):
    """Verifica halfword inside a word traps outside main memory.

    The flash and the peripheral window do not run a misaligned access,
    even inside a word.
    """
    for opcode, funct3, cause in IN_WORD:
        for base in OUTSIDE_MAIN_MEMORY:
            assert await probe(dut, opcode, funct3, ea=base + 1) == (
                1,
                0,
                cause,
                base + 1,
            ), (opcode, funct3, hex(base))


@cocotb.test()
async def test_access_crossing_a_word_is_executed_in_main_memory(dut):
    """Verifica access crossing a word is executed in main memory.

    An access that spans two words of the RAM or of the SDRAM does not
    trap.
    """
    for opcode, funct3, offset, _ in CROSSING:
        for base in MAIN_MEMORY:
            assert (await probe(dut, opcode, funct3, ea=base + offset))[
                0
            ] == 0, (opcode, funct3, offset, hex(base))


@cocotb.test()
async def test_access_crossing_a_word_traps_outside_main_memory(dut):
    """Verifica access crossing a word traps outside main memory.

    The flash and the peripheral window do not run an access that spans
    two words.
    """
    for opcode, funct3, offset, cause in CROSSING:
        for base in OUTSIDE_MAIN_MEMORY:
            assert await probe(dut, opcode, funct3, ea=base + offset) == (
                1,
                0,
                cause,
                base + offset,
            ), (opcode, funct3, offset, hex(base))


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
        assert await probe(dut, opcode, funct3, ea=ea) == (1, 0, cause, ea), (
            opcode,
            funct3,
            hex(ea),
        )
    # the last word of each region still takes an access that stays
    # inside it
    assert (await probe(dut, OP_LOAD, 0b010, ea=0x3FFFFFF9))[0] == 0
    assert (await probe(dut, OP_STORE, 0b010, ea=0x7FFFFFF9))[0] == 0
