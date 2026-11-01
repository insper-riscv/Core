"""Testes de HazardDetectionUnit."""

import cocotb
from cocotb.triggers import Timer


def set_inputs(
    dut,
    ifid_rs1: int,
    ifid_rs2: int,
    idex_rd: int,
    idex_reRAM: int,
    muldiv_busy: int,
    ifid_valid: int = 1,
    ifid_opcode: str = "0110011",
    exmem_rd: int = 0,
    exmem_reRAM: int = 0,
) -> None:
    # ifid_opcode default="0110011" = R-type (usa rs1 e rs2)
    """Executa set inputs."""
    dut.i_ifid_rs1.value = ifid_rs1 & 0x1F
    dut.i_ifid_rs2.value = ifid_rs2 & 0x1F
    dut.i_idex_rd.value = idex_rd & 0x1F
    dut.i_idex_re_ram.value = idex_reRAM & 0x1
    dut.i_stall.value = muldiv_busy & 0x1
    dut.i_exmem_rd.value = exmem_rd & 0x1F
    dut.i_exmem_re_ram.value = exmem_reRAM & 0x1
    dut.i_ifid_valid.value = ifid_valid & 0x1
    dut.i_ifid_opcode.value = int(ifid_opcode, 2)


def check_outputs(
    dut, exp_pc_we: int, exp_ifid_we: int, exp_bubble: int, msg: str = ""
) -> None:
    """Executa check outputs."""
    assert int(dut.o_pc_we.value) == exp_pc_we, (
        f"{msg}: o_pc_we esperado={exp_pc_we} obtido={int(dut.o_pc_we.value)}"
    )
    assert int(dut.o_ifid_we.value) == exp_ifid_we, (
        f"{msg}: o_ifid_we esperado={exp_ifid_we} "
        f"obtido={int(dut.o_ifid_we.value)}"
    )
    assert int(dut.o_bubble_sel.value) == exp_bubble, (
        f"{msg}: o_bubble_sel esperado={exp_bubble} "
        f"obtido={int(dut.o_bubble_sel.value)}"
    )


@cocotb.test()
async def test_no_hazard(dut):
    """Verifica no hazard.

    Sem hazards: instrucao em EX nao e load ou rd != rs1/rs2 da
    instrucao em ID. Pipeline deve fluir normalmente.
    """
    set_inputs(
        dut, ifid_rs1=1, ifid_rs2=2, idex_rd=5, idex_reRAM=0, muldiv_busy=0
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
    dut._log.info("test_no_hazard: OK")


@cocotb.test()
async def test_load_use_hazard_rs1(dut):
    """Detecta load-use hazard em rs1.

    Instrucao em EX e load com rd=5, instrucao em ID usa rs1=5.
    """
    set_inputs(
        dut, ifid_rs1=5, ifid_rs2=2, idex_rd=5, idex_reRAM=1, muldiv_busy=0
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    dut._log.info("test_load_use_hazard_rs1: OK")


@cocotb.test()
async def test_load_use_hazard_rs2(dut):
    """Verifica load use hazard rs2.

    Load-use hazard: load em EX com rd=10, instrucao em ID usa rs2=10.
    """
    set_inputs(
        dut, ifid_rs1=1, ifid_rs2=10, idex_rd=10, idex_reRAM=1, muldiv_busy=0
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    dut._log.info("test_load_use_hazard_rs2: OK")


@cocotb.test()
async def test_muldiv_busy(dut):
    """Verifica muldiv busy.

    muldiv_busy='1' deve congelar o pipeline mesmo sem load-use hazard.
    """
    set_inputs(
        dut, ifid_rs1=1, ifid_rs2=2, idex_rd=5, idex_reRAM=0, muldiv_busy=1
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    dut._log.info("test_muldiv_busy: OK")


@cocotb.test()
async def test_no_hazard_x0_destination(dut):
    """Verifica no hazard x0 destination.

    Mesmo com load em EX e rd coincidindo, se rd=x0 nao deve haver
    hazard (x0 e sempre zero).
    """
    set_inputs(
        dut, ifid_rs1=0, ifid_rs2=0, idex_rd=0, idex_reRAM=1, muldiv_busy=0
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
    dut._log.info("test_no_hazard_x0_destination: OK")


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
            idex_reRAM=1,
            muldiv_busy=0,
        )
        await Timer(1, units="ns")
        check_outputs(
            dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1, msg=f"rd=rs1={rd}"
        )
    dut._log.info("test_all_registers: OK")


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
        idex_reRAM=0,
        muldiv_busy=0,
        exmem_rd=3,
        exmem_reRAM=1,
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1, msg="rs1")
    set_inputs(
        dut,
        ifid_rs1=1,
        ifid_rs2=4,
        idex_rd=9,
        idex_reRAM=0,
        muldiv_busy=0,
        exmem_rd=4,
        exmem_reRAM=1,
    )
    await Timer(1, units="ns")
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
        idex_reRAM=0,
        muldiv_busy=0,
        exmem_rd=3,
        exmem_reRAM=0,
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)


@cocotb.test()
async def test_load_in_mem_stage_with_x0_destination(dut):
    """Load em MEM com destino x0 nunca causa espera."""
    set_inputs(
        dut,
        ifid_rs1=0,
        ifid_rs2=0,
        idex_rd=9,
        idex_reRAM=0,
        muldiv_busy=0,
        exmem_rd=0,
        exmem_reRAM=1,
    )
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
