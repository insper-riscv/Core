"""Testes de HazardDetectionUnit."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal, log_info

# Entrada -> (porta, máscara de bits)
INPUTS = {
    "ifid_rs1": ("i_ifid_rs1", 0x1F),
    "ifid_rs2": ("i_ifid_rs2", 0x1F),
    "idex_rd": ("i_idex_rd", 0x1F),
    "idex_reram": ("i_idex_re_ram", 0x1),
    "muldiv_busy": ("i_stall", 0x1),
    "ifid_valid": ("i_ifid_valid", 0x1),
    "exmem_rd": ("i_exmem_rd", 0x1F),
    "exmem_reram": ("i_exmem_re_ram", 0x1),
}
# ifid_opcode "0110011" é R-type (usa rs1 e rs2)
DEFAULTS = {"ifid_valid": 1, "exmem_rd": 0, "exmem_reram": 0}


def set_inputs(dut, ifid_opcode: str = "0110011", **inputs: int) -> None:
    """Apresenta as entradas da unidade de hazard, mascaradas."""
    values = DEFAULTS | inputs
    missing = INPUTS.keys() - values.keys()
    unknown = values.keys() - INPUTS.keys()
    if missing or unknown:
        raise TypeError(f"entradas: faltam {missing}, sobram {unknown}")
    for name, (port, mask) in INPUTS.items():
        getattr(dut, port).value = values[name] & mask
    dut.i_ifid_opcode.value = int(ifid_opcode, 2)


def check_outputs(
    dut, exp_pc_we: int, exp_ifid_we: int, exp_bubble: int, msg: str = ""
) -> None:
    """Executa check outputs."""
    check_equal(
        int(dut.o_pc_we.value),
        exp_pc_we,
        f"{msg}: o_pc_we esperado={exp_pc_we} obtido={int(dut.o_pc_we.value)}",
    )
    check_equal(
        int(dut.o_ifid_we.value),
        exp_ifid_we,
        f"{msg}: o_ifid_we esperado={exp_ifid_we} "
        f"obtido={int(dut.o_ifid_we.value)}",
    )
    check_equal(
        int(dut.o_bubble_sel.value),
        exp_bubble,
        f"{msg}: o_bubble_sel esperado={exp_bubble} "
        f"obtido={int(dut.o_bubble_sel.value)}",
    )


@cocotb.test()
async def test_no_hazard(dut):
    """Verifica no hazard.

    Sem hazards: instrucao em EX nao e load ou rd != rs1/rs2 da
    instrucao em ID. Pipeline deve fluir normalmente.
    """
    set_inputs(
        dut, ifid_rs1=1, ifid_rs2=2, idex_rd=5, idex_reram=0, muldiv_busy=0
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
    log_info("test_no_hazard: OK")


@cocotb.test()
async def test_load_use_hazard_rs1(dut):
    """Detecta load-use hazard em rs1.

    Instrucao em EX e load com rd=5, instrucao em ID usa rs1=5.
    """
    set_inputs(
        dut, ifid_rs1=5, ifid_rs2=2, idex_rd=5, idex_reram=1, muldiv_busy=0
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    log_info("test_load_use_hazard_rs1: OK")


@cocotb.test()
async def test_load_use_hazard_rs2(dut):
    """Verifica load use hazard rs2.

    Load-use hazard: load em EX com rd=10, instrucao em ID usa rs2=10.
    """
    set_inputs(
        dut, ifid_rs1=1, ifid_rs2=10, idex_rd=10, idex_reram=1, muldiv_busy=0
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    log_info("test_load_use_hazard_rs2: OK")


@cocotb.test()
async def test_muldiv_busy(dut):
    """Verifica muldiv busy.

    muldiv_busy='1' deve congelar o pipeline mesmo sem load-use hazard.
    """
    set_inputs(
        dut, ifid_rs1=1, ifid_rs2=2, idex_rd=5, idex_reram=0, muldiv_busy=1
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    log_info("test_muldiv_busy: OK")


@cocotb.test()
async def test_no_hazard_x0_destination(dut):
    """Verifica no hazard x0 destination.

    Mesmo com load em EX e rd coincidindo, se rd=x0 nao deve haver
    hazard (x0 e sempre zero).
    """
    set_inputs(
        dut, ifid_rs1=0, ifid_rs2=0, idex_rd=0, idex_reram=1, muldiv_busy=0
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
    log_info("test_no_hazard_x0_destination: OK")


@cocotb.test()
async def test_all_registers(dut):
    """Detecta hazard para todos os registradores.

    Vale para cada par (rd, rs1) com rd != 0 e rd == rs1, load em EX.
    """
    for rd in range(1, 32):
        set_inputs(
            dut,
            ifid_rs1=rd,
            ifid_rs2=0,
            idex_rd=rd,
            idex_reram=1,
            muldiv_busy=0,
        )
        await Timer(1, unit="ns")
        check_outputs(
            dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1, msg=f"rd=rs1={rd}"
        )
    log_info("test_all_registers: OK")


@cocotb.test()
async def test_load_in_mem_stage_also_stalls(dut):
    """Verifica load in mem stage also stalls.

    Um load em MEM ainda nao entregou o dado alinhado: o dependente
    espera mais um ciclo.
    """
    set_inputs(
        dut,
        ifid_rs1=3,
        ifid_rs2=2,
        idex_rd=9,
        idex_reram=0,
        muldiv_busy=0,
        exmem_rd=3,
        exmem_reram=1,
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1, msg="rs1")
    set_inputs(
        dut,
        ifid_rs1=1,
        ifid_rs2=4,
        idex_rd=9,
        idex_reram=0,
        muldiv_busy=0,
        exmem_rd=4,
        exmem_reram=1,
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1, msg="rs2")


@cocotb.test()
async def test_non_load_in_mem_stage_does_not_stall(dut):
    """Verifica non load in mem stage does not stall.

    Um resultado de ULA em MEM ja e adiantado de EX/MEM: sem espera.
    """
    set_inputs(
        dut,
        ifid_rs1=3,
        ifid_rs2=2,
        idex_rd=9,
        idex_reram=0,
        muldiv_busy=0,
        exmem_rd=3,
        exmem_reram=0,
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)


@cocotb.test()
async def test_load_in_mem_stage_with_x0_destination(dut):
    """Load em MEM com destino x0 nunca causa espera."""
    set_inputs(
        dut,
        ifid_rs1=0,
        ifid_rs2=0,
        idex_rd=9,
        idex_reram=0,
        muldiv_busy=0,
        exmem_rd=0,
        exmem_reram=1,
    )
    await Timer(1, unit="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
