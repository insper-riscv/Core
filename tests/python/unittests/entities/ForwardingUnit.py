import cocotb
from cocotb.triggers import Timer


def set_inputs(dut, ex_rs1_idx, ex_rs2_idx, exmem_rd_idx, exmem_weReg,
               memwb_rd_idx, memwb_weReg):
    dut.ex_rs1_idx.value   = ex_rs1_idx & 0x1F
    dut.ex_rs2_idx.value   = ex_rs2_idx & 0x1F
    dut.exmem_rd_idx.value = exmem_rd_idx & 0x1F
    dut.exmem_weReg.value  = exmem_weReg & 0x1
    dut.memwb_rd_idx.value = memwb_rd_idx & 0x1F
    dut.memwb_weReg.value  = memwb_weReg & 0x1


@cocotb.test()
async def test_no_forwarding(dut):
    """Sem dependencias: nenhum forward."""
    set_inputs(dut, ex_rs1_idx=1, ex_rs2_idx=2, exmem_rd_idx=5, exmem_weReg=1,
               memwb_rd_idx=6, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 0, f"forward_A esperado=0 obtido={int(dut.forward_A.value)}"
    assert int(dut.forward_B.value) == 0, f"forward_B esperado=0 obtido={int(dut.forward_B.value)}"
    dut._log.info("test_no_forwarding: OK")


@cocotb.test()
async def test_forward_ex_mem_rs1(dut):
    """Forward EX/MEM para rs1: instrucao anterior escrevera em rd=5,
    instrucao atual le rs1=5."""
    set_inputs(dut, ex_rs1_idx=5, ex_rs2_idx=2, exmem_rd_idx=5, exmem_weReg=1,
               memwb_rd_idx=6, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 2, f"forward_A esperado=2 obtido={int(dut.forward_A.value)}"
    assert int(dut.forward_B.value) == 0
    dut._log.info("test_forward_ex_mem_rs1: OK")


@cocotb.test()
async def test_forward_ex_mem_rs2(dut):
    """Forward EX/MEM para rs2."""
    set_inputs(dut, ex_rs1_idx=1, ex_rs2_idx=5, exmem_rd_idx=5, exmem_weReg=1,
               memwb_rd_idx=6, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 0
    assert int(dut.forward_B.value) == 2, f"forward_B esperado=2 obtido={int(dut.forward_B.value)}"
    dut._log.info("test_forward_ex_mem_rs2: OK")


@cocotb.test()
async def test_forward_mem_wb_rs1(dut):
    """Forward MEM/WB para rs1 (sem hazard EX/MEM)."""
    set_inputs(dut, ex_rs1_idx=6, ex_rs2_idx=2, exmem_rd_idx=5, exmem_weReg=1,
               memwb_rd_idx=6, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 1, f"forward_A esperado=1 obtido={int(dut.forward_A.value)}"
    assert int(dut.forward_B.value) == 0
    dut._log.info("test_forward_mem_wb_rs1: OK")


@cocotb.test()
async def test_forward_mem_wb_rs2(dut):
    """Forward MEM/WB para rs2 (sem hazard EX/MEM)."""
    set_inputs(dut, ex_rs1_idx=1, ex_rs2_idx=6, exmem_rd_idx=5, exmem_weReg=1,
               memwb_rd_idx=6, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 0
    assert int(dut.forward_B.value) == 1, f"forward_B esperado=1 obtido={int(dut.forward_B.value)}"
    dut._log.info("test_forward_mem_wb_rs2: OK")


@cocotb.test()
async def test_priority_ex_mem_over_mem_wb(dut):
    """Quando ambos EX/MEM e MEM/WB tem rd igual ao rs, EX/MEM tem prioridade
    (resultado mais recente)."""
    set_inputs(dut, ex_rs1_idx=5, ex_rs2_idx=5, exmem_rd_idx=5, exmem_weReg=1,
               memwb_rd_idx=5, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 2
    assert int(dut.forward_B.value) == 2
    dut._log.info("test_priority_ex_mem_over_mem_wb: OK")


@cocotb.test()
async def test_x0_never_forwards(dut):
    """rd=x0 nunca deve causar forwarding (x0 e sempre zero)."""
    set_inputs(dut, ex_rs1_idx=0, ex_rs2_idx=0, exmem_rd_idx=0, exmem_weReg=1,
               memwb_rd_idx=0, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 0
    assert int(dut.forward_B.value) == 0
    dut._log.info("test_x0_never_forwards: OK")


@cocotb.test()
async def test_we_zero_never_forwards(dut):
    """Mesmo com rd igual, se weReg='0' nao deve forward.
    Casos tipicos: branch, store, instrucoes que nao escrevem registrador."""
    set_inputs(dut, ex_rs1_idx=5, ex_rs2_idx=5, exmem_rd_idx=5, exmem_weReg=0,
               memwb_rd_idx=5, memwb_weReg=0)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 0
    assert int(dut.forward_B.value) == 0
    dut._log.info("test_we_zero_never_forwards: OK")


@cocotb.test()
async def test_both_operands_forwarded(dut):
    """Forward simultaneo nos dois operandos: EX/MEM para rs1 e MEM/WB para rs2."""
    set_inputs(dut, ex_rs1_idx=5, ex_rs2_idx=6, exmem_rd_idx=5, exmem_weReg=1,
               memwb_rd_idx=6, memwb_weReg=1)
    await Timer(1, units="ns")
    assert int(dut.forward_A.value) == 2
    assert int(dut.forward_B.value) == 1
    dut._log.info("test_both_operands_forwarded: OK")


@cocotb.test()
async def test_all_register_pairs(dut):
    """Para cada rd em x1..x31, verifica que forwarding e detectado tanto
    para rs1 quanto para rs2."""
    for rd in range(1, 32):
        # EX/MEM forward para rs1
        set_inputs(dut, ex_rs1_idx=rd, ex_rs2_idx=0, exmem_rd_idx=rd, exmem_weReg=1,
                   memwb_rd_idx=0, memwb_weReg=0)
        await Timer(1, units="ns")
        assert int(dut.forward_A.value) == 2, f"EX/MEM rs1 rd={rd}"
        # EX/MEM forward para rs2
        set_inputs(dut, ex_rs1_idx=0, ex_rs2_idx=rd, exmem_rd_idx=rd, exmem_weReg=1,
                   memwb_rd_idx=0, memwb_weReg=0)
        await Timer(1, units="ns")
        assert int(dut.forward_B.value) == 2, f"EX/MEM rs2 rd={rd}"
    dut._log.info("test_all_register_pairs: OK")
