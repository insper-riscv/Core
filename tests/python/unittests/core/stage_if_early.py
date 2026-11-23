"""Testes de stage_if com o endereço adiantado às memórias de instrução.

As memórias leem, na borda do clock do núcleo, o endereço que o PC terá
no ciclo seguinte (o_if_addr_nx), sem a decisão tardia de EX. Depois de
um desvio, salto ou exceção, o PC carrega o alvo, a leitura daquele
ciclo foi do endereço sequencial (a instrução não vale, vira bolha e
não é falta da cache) e o PC fica parado um ciclo, enquanto as memórias
leem o alvo.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal

SDRAM = 0x40000000
IDLE = {
    "hdu_pc_we": 1,
    "pipe_run": 1,
    "ex_branch_taken": 0,
    "ex_jalr_taken": 0,
    "trap_take": 0,
    "mret_take": 0,
    "fencei_take": 0,
    "ic_inval": 0,
    "branch_target": SDRAM + 0x100,
    "jalr_target": SDRAM + 0x200,
    "redirect_pc": SDRAM + 0x300,
    "boot_memory_data": 0xB0B0B0B0,
    "flash_data": 0xF1A5F1A5,
    "ic_data": 0x1CAC4E00,
    "ic_ready": 1,
    "ifid_en": 1,
    "flush_if_id": 0,
    "ifid_pc": 0,
}


async def apply(dut, values):
    """Aplica as entradas (sobre IDLE) e espera a propagação."""
    dut.i_rst.value = 0
    for name, value in (IDLE | values).items():
        getattr(dut, f"i_{name}").value = value
    await Timer(1, unit="ns")


async def step(dut, values):
    """Aplica as entradas e avança uma borda.

    Devolve (PC novo, endereço lido na borda).
    """
    await apply(dut, values)
    read = int(dut.o_if_addr_nx.value)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return int(dut.o_pc.value), read


async def start(dut):
    """Liga o clock, aplica reset e leva o PC à região da cache."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await apply(dut, {"rst": 1})
    await RisingEdge(dut.i_clk)
    pc, _ = await step(dut, {"trap_take": 1, "redirect_pc": SDRAM})
    check_equal(pc, SDRAM, "redirecionamento")
    # o ciclo seguinte ao alvo está parado
    pc, read = await step(dut, {})
    check_equal((pc, read), (SDRAM, SDRAM), "parado no alvo")


@cocotb.test()
async def test_read_address_is_the_next_pc(dut):
    """Sem decisão de EX, o endereço lido é o PC seguinte."""
    await start(dut)
    for index in range(1, 6):
        pc, read = await step(dut, {})
        check_equal(read, pc, f"endereço lido {index}")
        check_equal(pc, SDRAM + 4 * index, f"PC {index}")


@cocotb.test()
async def test_stall_reads_the_same_address(dut):
    """Com o PC parado as memórias leem de novo o PC atual."""
    await start(dut)
    await step(dut, {})
    for _ in range(3):
        pc, read = await step(dut, {"hdu_pc_we": 0})
        check_equal((pc, read), (SDRAM + 4, SDRAM + 4), "parado")


@cocotb.test()
async def test_branch_target_costs_one_cycle(dut):
    """O alvo de um desvio chega à leitura um ciclo depois."""
    await start(dut)
    await step(dut, {})
    # EX decide o desvio nesta borda: as memórias leem PC + 4 e o PC
    # vira o alvo
    pc, read = await step(dut, {"ex_branch_taken": 1})
    check_equal(pc, SDRAM + 0x100, "PC é o alvo")
    check_equal(read, SDRAM + 8, "leitura sequencial, decisão tardia")
    # a instrução deste ciclo não vale: bolha, sem falta da cache
    await apply(dut, {"ic_ready": 0})
    check_equal(int(dut.o_instr_valid.value), 0, "bolha")
    check_equal(int(dut.o_replay.value), 0, "sem repetição")
    check_equal(int(dut.o_if_addr_nx.value), SDRAM + 0x100, "lê o alvo")
    pc, read = await step(dut, {"ic_ready": 0})
    check_equal((pc, read), (SDRAM + 0x100, SDRAM + 0x100), "PC espera")
    # agora a leitura é a do alvo
    await apply(dut, {})
    check_equal(int(dut.o_instr_valid.value), 1, "instrução do alvo")
    check_equal(int(dut.o_instr.value), IDLE["ic_data"], "dado da cache")
    pc, read = await step(dut, {})
    check_equal((pc, read), (SDRAM + 0x104, SDRAM + 0x104), "segue")


@cocotb.test()
async def test_redirect_and_jalr_cost_one_cycle(dut):
    """Salto indireto e redirecionamento esperam o mesmo ciclo."""
    await start(dut)
    for values, target in (
        ({"ex_jalr_taken": 1}, SDRAM + 0x200),
        ({"trap_take": 1}, SDRAM + 0x300),
        ({"mret_take": 1}, SDRAM + 0x300),
        ({"fencei_take": 1}, SDRAM + 0x300),
    ):
        pc, _ = await step(dut, values)
        check_equal(pc, target, values)
        await apply(dut, {})
        check_equal(int(dut.o_instr_valid.value), 0, f"bolha {values}")
        pc, read = await step(dut, {})
        check_equal((pc, read), (target, target), f"espera {values}")
        await apply(dut, {})
        check_equal(int(dut.o_instr_valid.value), 1, f"alvo {values}")


@cocotb.test()
async def test_new_decision_in_the_wait_cycle(dut):
    """Uma exceção no ciclo de espera carrega o PC e espera de novo."""
    await start(dut)
    await step(dut, {"ex_branch_taken": 1})
    pc, _ = await step(dut, {"trap_take": 1})
    check_equal(pc, SDRAM + 0x300, "redirecionado na espera")
    await apply(dut, {})
    check_equal(int(dut.o_instr_valid.value), 0, "bolha de novo")
    pc, read = await step(dut, {})
    check_equal((pc, read), (SDRAM + 0x300, SDRAM + 0x300), "espera")
