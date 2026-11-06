"""Testes de stage_if: busca de instrução e escolha do próximo PC.

O PC é carregado por redirecionamento (trap, MRET, FENCE.I), JALR ou
desvio, nessa prioridade, ou avança de 4 em 4; o endereço escolhe a
fonte da instrução (BOOT_MEMORY, FLASH ou I-cache da região SDRAM) e a
espera da I-cache congela o PC.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

BOOT, FLASH, SDRAM = 0x0, 0x2000, 0x40000000
IDLE = {
    "hdu_pc_we": 0,
    "pipe_run": 1,
    "ex_branch_taken": 0,
    "ex_jalr_taken": 0,
    "trap_take": 0,
    "mret_take": 0,
    "fencei_take": 0,
    "ic_inval": 0,
    "branch_target": 0x1111,
    "jalr_target": 0x2222,
    "redirect_pc": 0x3333,
    "boot_memory_data": 0xB0B0B0B0,
    "flash_data": 0xF1A5F1A5,
    "ic_data": 0x1CAC4E00,
    "ic_ready": 1,
}


async def start(dut):
    """Liga o clock e aplica reset, deixando o PC em zero."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await apply(dut, {"rst": 1})
    await RisingEdge(dut.i_clk)
    await apply(dut, {})


async def apply(dut, values):
    """Aplica as entradas (sobre IDLE) e espera a propagação."""
    dut.i_rst.value = 0
    for name, value in (IDLE | values).items():
        getattr(dut, f"i_{name}").value = value
    await Timer(1, unit="ns")


async def step(dut, values):
    """Aplica as entradas, avança uma borda e devolve o PC novo."""
    await apply(dut, values)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return int(dut.o_pc.value)


async def goto(dut, address):
    """Leva o PC a um endereço por redirecionamento."""
    pc = await step(dut, {"trap_take": 1, "redirect_pc": address})
    check_equal(pc, address, "redirecionamento")


@cocotb.test()
async def test_sequential_and_stall(dut):
    """O PC avança com a HDU liberada e congela sem ela."""
    await start(dut)
    check_equal(int(dut.o_pc.value), 0, "PC no reset")
    check_equal(int(dut.o_pc4.value), 4, "PC + 4")
    for index in range(1, 4):
        check_equal(await step(dut, {"hdu_pc_we": 1}), 4 * index, index)
    for _ in range(3):
        check_equal(await step(dut, {}), 12, "stall")
    check_equal(int(dut.o_if_addr.value), 12, "endereço de busca")
    check_equal(int(dut.o_if_rden.value), 1, "leitura sempre habilitada")


@cocotb.test()
async def test_next_pc_priority(dut):
    """Redirecionamento, JALR e desvio, nessa ordem de prioridade."""
    await start(dut)
    sources = (
        ({"ex_branch_taken": 1}, 0x1111),
        ({"ex_branch_taken": 1, "ex_jalr_taken": 1}, 0x2222),
        ({"ex_jalr_taken": 1, "mret_take": 1}, 0x3333),
        ({"ex_branch_taken": 1, "fencei_take": 1}, 0x3333),
        ({"ex_branch_taken": 1, "trap_take": 1}, 0x3333),
    )
    for values, target in sources:
        check_equal(await step(dut, values), target, values)


@cocotb.test()
async def test_branch_needs_pipeline_running(dut):
    """Desvio e JALR só carregam o PC com o pipeline avançando."""
    await start(dut)
    for name in ("ex_branch_taken", "ex_jalr_taken"):
        held = await step(dut, {name: 1, "pipe_run": 0})
        check_equal(held, 0, name)
    check_equal(await step(dut, {"trap_take": 1, "pipe_run": 0}), 0x3333, "")


@cocotb.test()
async def test_instruction_source_by_region(dut):
    """A região do PC escolhe a fonte da instrução."""
    await start(dut)
    for address, source, sdram in (
        (BOOT, "boot_memory_data", 0),
        (0xFFC, "boot_memory_data", 0),
        (0x1000, "flash_data", 0),
        (FLASH, "flash_data", 0),
        (SDRAM, "ic_data", 1),
    ):
        await goto(dut, address)
        await apply(dut, {})
        check_equal(int(dut.o_instr.value), IDLE[source], hex(address))
        check_equal(int(dut.o_ic_sel.value), sdram, hex(address))
        check_equal(int(dut.o_instr_valid.value), 1, hex(address))


@cocotb.test()
async def test_icache_wait_holds_pc(dut):
    """Sem a palavra da I-cache o PC congela."""
    await start(dut)
    await goto(dut, SDRAM)
    for _ in range(3):
        await apply(dut, {"hdu_pc_we": 1, "ic_ready": 0})
        check_equal(int(dut.o_instr_valid.value), 0, "espera")
        check_equal(
            await step(dut, {"hdu_pc_we": 1, "ic_ready": 0}), SDRAM, "PC"
        )
    check_equal(await step(dut, {"hdu_pc_we": 1}), SDRAM + 4, "libera")
    await apply(dut, {"ic_inval": 1})
    check_equal(int(dut.o_ic_inval.value), 1, "invalidação repassada")
