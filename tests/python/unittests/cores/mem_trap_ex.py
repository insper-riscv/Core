"""Testes do modulo.

A load or store that traps in MEM discards the instruction behind it in
EX.

The address exception of a load or store is decided in the MEM stage, so
the instruction that follows it is already in EX when the trap is taken.
Each case puts one instruction with a visible effect right behind a
faulting access (a CSR write, a store, a register write or a taken
branch) and resumes the program past it from the handler. The effect
must not appear, the handler must see the PC and the address of the
faulting access, and the retirement counter must not count the access
nor the instruction behind it.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import (
    LOG_BASE,
    MCAUSE,
    MEPC,
    MRET,
    MTVEC,
    NOP,
    csrrs,
    csrrw,
)
from tests.python.unittests.cores.misaligned_half import lh, sh
from tests.python.unittests.cores.sdram_stall import (
    _r,
    addi,
    beq,
    jal_self,
    lui,
    sw,
)

HANDLER_WORD = 160
MSCRATCH, MTVAL = 0x340, 0x343
MINSTRET, MHPMEVENT3, MHPMCOUNTER3 = 0xB02, 0x323, 0xB03
TAKEN_BRANCH_EVENT = 3
VICTIM_VALUE = 0x123
SCRATCH_RESET = 0
HANDLER_RETIRES = 9
LOG_WORDS = 3

# Registers of the program.
RAM, LOG, FLASH_BASE, PERIPH_BASE = 7, 11, 15, 16
VALUE, COUNT, RESUME = 9, 10, 27

FAULTS = {
    "load": (lh(24, FLASH_BASE, 1), 4, 0x1001),
    "store": (sh(VALUE, PERIPH_BASE, 1), 6, 0x80000001),
}


def _victims():
    """Return the instructions that must leave no trace, by name."""
    return {
        "csr": csrrw(0, MSCRATCH, VALUE),
        "store": sw(VALUE, RAM, 0x300),
        "register": addi(COUNT, COUNT, 1),
        "branch": beq(0, 0, 8),
    }


def _prologue():
    """Return the setup: handler, bases, victim value and event."""
    return [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(RAM, RAM_BASE >> 12),
        lui(LOG, LOG_BASE >> 12),
        addi(LOG, LOG, LOG_BASE & 0xFFF),
        lui(FLASH_BASE, 1),
        lui(PERIPH_BASE, 0x80000),
        addi(VALUE, 0, VICTIM_VALUE),
        addi(5, 0, TAKEN_BRANCH_EVENT),
        csrrw(0, MHPMEVENT3, 5),
    ]


def _case(start, fault, victim):
    """Return the words of one case, laid out from word `start`.

    The case reads minstret, runs the faulting access and the victim,
    and the handler resumes right after the victim, where minstret is
    read again and the difference is stored in the first RAM word.
    """
    resume = start + 5
    return [
        addi(RESUME, 0, 4 * resume),
        csrrs(20, MINSTRET, 0),
        fault,
        victim,
        NOP,
        csrrs(21, MINSTRET, 0),
        _r(22, 0, 21, 20, 0x20),
        sw(22, RAM, 0),
    ]


def _handler():
    """Return the handler: log the trap, resume at x27."""
    return [
        csrrs(6, MCAUSE, 0),
        sw(6, LOG, 0),
        csrrs(28, MEPC, 0),
        sw(28, LOG, 4),
        csrrs(29, MTVAL, 0),
        sw(29, LOG, 8),
        addi(LOG, LOG, 4 * LOG_WORDS),
        csrrw(0, MEPC, RESUME),
        MRET,
    ]


def _epilogue():
    """Return the reads of the effects, stored after the cases."""
    return [
        csrrs(23, MSCRATCH, 0),
        sw(23, RAM, 0x200),
        csrrs(23, MHPMCOUNTER3, 0),
        sw(23, RAM, 0x204),
        sw(COUNT, RAM, 0x208),
        addi(14, 0, 1),
        sw(14, RAM, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]


def build(fault_name, victim_name):
    """Assemble the program of one case and the PC of its access."""
    fault, _, _ = FAULTS[fault_name]
    program = _prologue()
    access_pc = 4 * (len(program) + 2)
    program += _case(len(program), fault, _victims()[victim_name])
    program += _epilogue()
    check_true(len(program) < HANDLER_WORD, len(program))
    program += [NOP] * (HANDLER_WORD - len(program)) + _handler()
    return program, access_pc


async def _run(dut, fault_name, victim_name):
    """Run one case and check what the faulting access leaves behind."""
    program, access_pc = build(fault_name, victim_name)
    _, cause, address = FAULTS[fault_name]
    ram = await run_program(dut, program, max_cycles=3000)
    name = f"{fault_name} then {victim_name}"
    check_equal(ram.get(LOG_BASE), cause, f"{name}: mcause")
    check_equal(ram.get(LOG_BASE + 4), access_pc, f"{name}: mepc")
    check_equal(ram.get(LOG_BASE + 8), address, f"{name}: mtval")
    check_true(LOG_BASE + 12 not in ram, f"{name}: more than one trap")
    check_equal(ram.get(RAM_BASE + 0x200), SCRATCH_RESET, f"{name}: CSR")
    check_equal(ram.get(RAM_BASE + 0x204), 0, f"{name}: branch counted")
    check_equal(ram.get(RAM_BASE + 0x208), 0, f"{name}: register written")
    check_true(RAM_BASE + 0x300 not in ram, f"{name}: store written")
    check_equal(
        ram.get(RAM_BASE),
        1 + HANDLER_RETIRES,
        f"{name}: retired instructions between the two reads",
    )


@cocotb.test()
async def test_load_trap_discards_a_csr_write(dut):
    """Verifica a CSR write behind a trapping load does not commit."""
    await _run(dut, "load", "csr")


@cocotb.test()
async def test_load_trap_discards_a_store(dut):
    """Verifica a store behind a trapping load does not write."""
    await _run(dut, "load", "store")


@cocotb.test()
async def test_load_trap_discards_a_register_write(dut):
    """Verifica a register write behind a trapping load is dropped."""
    await _run(dut, "load", "register")


@cocotb.test()
async def test_load_trap_discards_a_taken_branch(dut):
    """Verifica a taken branch behind a trapping load is not counted."""
    await _run(dut, "load", "branch")


@cocotb.test()
async def test_store_trap_discards_a_csr_write(dut):
    """Verifica a CSR write behind a trapping store does not commit."""
    await _run(dut, "store", "csr")


@cocotb.test()
async def test_store_trap_discards_a_store(dut):
    """Verifica a store behind a trapping store does not write."""
    await _run(dut, "store", "store")


@cocotb.test()
async def test_store_trap_discards_a_register_write(dut):
    """Verifica a register write behind a trapping store is dropped."""
    await _run(dut, "store", "register")


@cocotb.test()
async def test_store_trap_discards_a_taken_branch(dut):
    """Verifica a taken branch behind a trapping store is dropped."""
    await _run(dut, "store", "branch")
