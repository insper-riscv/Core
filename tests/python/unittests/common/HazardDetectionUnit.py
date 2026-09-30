import cocotb
from cocotb.triggers import Timer


def set_inputs(dut, ifid_rs1: int, ifid_rs2: int, idex_rd: int,
               idex_reRAM: int, muldiv_busy: int,
               ifid_valid: int = 1,
               ifid_opcode: str = "0110011") -> None:
    # ifid_opcode default="0110011" = R-type (usa rs1 e rs2)
    dut.ifid_rs1.value    = ifid_rs1 & 0x1F
    dut.ifid_rs2.value    = ifid_rs2 & 0x1F
    dut.idex_rd.value     = idex_rd & 0x1F
    dut.idex_reRAM.value  = idex_reRAM & 0x1
    dut.muldiv_busy.value = muldiv_busy & 0x1
    dut.ifid_valid.value  = ifid_valid & 0x1
    dut.ifid_opcode.value = int(ifid_opcode, 2)


def check_outputs(dut, exp_pc_we: int, exp_ifid_we: int, exp_bubble: int,
                  msg: str = "") -> None:
    assert int(dut.if_pc_write_en.value) == exp_pc_we, \
        f"{msg}: if_pc_write_en esperado={exp_pc_we} obtido={int(dut.if_pc_write_en.value)}"
    assert int(dut.ifid_write_en.value) == exp_ifid_we, \
        f"{msg}: ifid_write_en esperado={exp_ifid_we} obtido={int(dut.ifid_write_en.value)}"
    assert int(dut.id_bubble_sel.value) == exp_bubble, \
        f"{msg}: id_bubble_sel esperado={exp_bubble} obtido={int(dut.id_bubble_sel.value)}"


@cocotb.test()
async def test_no_hazard(dut):
    """Sem hazards: instrucao em EX nao e load ou rd != rs1/rs2 da instrucao em ID.
    Pipeline deve fluir normalmente."""
    set_inputs(dut, ifid_rs1=1, ifid_rs2=2, idex_rd=5, idex_reRAM=0, muldiv_busy=0)
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
    dut._log.info("test_no_hazard: OK")


@cocotb.test()
async def test_load_use_hazard_rs1(dut):
    """Load-use hazard: instrucao em EX e load com rd=5,
    instrucao em ID usa rs1=5. Deve detectar hazard."""
    set_inputs(dut, ifid_rs1=5, ifid_rs2=2, idex_rd=5, idex_reRAM=1, muldiv_busy=0)
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    dut._log.info("test_load_use_hazard_rs1: OK")


@cocotb.test()
async def test_load_use_hazard_rs2(dut):
    """Load-use hazard: load em EX com rd=10, instrucao em ID usa rs2=10."""
    set_inputs(dut, ifid_rs1=1, ifid_rs2=10, idex_rd=10, idex_reRAM=1, muldiv_busy=0)
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    dut._log.info("test_load_use_hazard_rs2: OK")


@cocotb.test()
async def test_muldiv_busy(dut):
    """muldiv_busy='1' deve congelar o pipeline mesmo sem load-use hazard."""
    set_inputs(dut, ifid_rs1=1, ifid_rs2=2, idex_rd=5, idex_reRAM=0, muldiv_busy=1)
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1)
    dut._log.info("test_muldiv_busy: OK")


@cocotb.test()
async def test_no_hazard_x0_destination(dut):
    """Mesmo com load em EX e rd coincidindo, se rd=x0 nao deve haver hazard
    (x0 e sempre zero)."""
    set_inputs(dut, ifid_rs1=0, ifid_rs2=0, idex_rd=0, idex_reRAM=1, muldiv_busy=0)
    await Timer(1, units="ns")
    check_outputs(dut, exp_pc_we=1, exp_ifid_we=1, exp_bubble=0)
    dut._log.info("test_no_hazard_x0_destination: OK")


@cocotb.test()
async def test_all_registers(dut):
    """Para cada par (rd, rs1) com rd != 0 e rd == rs1, com load em EX,
    deve detectar hazard."""
    for rd in range(1, 32):
        set_inputs(dut, ifid_rs1=rd, ifid_rs2=0, idex_rd=rd, idex_reRAM=1, muldiv_busy=0)
        await Timer(1, units="ns")
        check_outputs(dut, exp_pc_we=0, exp_ifid_we=0, exp_bubble=1,
                      msg=f"rd=rs1={rd}")
    dut._log.info("test_all_registers: OK")
