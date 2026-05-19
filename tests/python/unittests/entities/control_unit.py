import csv
from pathlib import Path
import cocotb
from cocotb.triggers import Timer


def _parse_field(val: str, width: int) -> int:
    """Converte campo da tabela para inteiro."""
    val = val.strip()
    if val == "-" or all(ch == "X" for ch in val):
        return 0

    symbol_map = {
        # opExImm[2:0]
        "U":       0b000,
        "I":       0b001,
        "I_shamt": 0b010,
        "J":       0b011,
        "S":       0b100,
        "B":       0b101,

        # opExRAM[2:0]
        "LW":  0b000,
        "LH":  0b001,
        "LHU": 0b010,
        "LB":  0b011,
        "LBU": 0b100,

        # opALU[4:0]
        "PASS_B": 0b00000,
        "ADD":    0b00001,
        "XOR":    0b00010,
        "OR":     0b00011,
        "AND":    0b00100,
        "SLL":    0b00101,
        "SRL":    0b00110,
        "SRA":    0b00111,
        "SUB":    0b01000,
        "SLT":    0b01001,
        "SLTU":   0b01010,
        "BEQ":    0b01011,
        "BNE":    0b01100,
        "BLT":    0b01101,
        "BGE":    0b01110,
        "BLTU":   0b01111,
        "BGEU":   0b10000,
        "JALR":   0b10001,
    }

    if val in symbol_map:
        return symbol_map[val]

    return int(val, 2)


def load_reference():
    """Carrega a tabela CSV de opcodes (mesma usada pelo InstructionDecoder)."""
    data_dir = Path(__file__).resolve().parent / "data"
    csv_path = data_dir / "riscv_opcodes.csv"
    with open(csv_path, newline="") as f:
        return list(csv.DictReader(f))


def build_instruction(opcode: int, funct3: int, funct7: int) -> int:
    """Monta uma instrucao de 32 bits a partir dos campos.

    Layout R-type (suficiente para extrair opcode/funct3/funct7):
      [31:25]=funct7  [24:20]=rs2  [19:15]=rs1
      [14:12]=funct3  [11:7]=rd    [6:0]=opcode
    rs1, rs2, rd nao afetam a decisao do control_unit, ficam zero.
    """
    instr = 0
    instr |= (opcode & 0x7F)
    instr |= (funct3 & 0x7) << 12
    instr |= (funct7 & 0x7F) << 25
    return instr & 0xFFFFFFFF


@cocotb.test()
async def test_control_unit(dut):
    """
    Para cada linha da tabela CSV:
    - monta a instrucao de 32 bits a partir de opcode/funct3/funct7
    - aplica em dut.instruction
    - espera propagacao
    - compara todos os sinais de saida com a tabela
    - verifica que opCode e funct3_out (saidas novas) batem com a entrada
    """
    ref_table = load_reference()

    for row in ref_table:
        inst_name = row["INST"]
        opcode = int(row["OpCode[6:0]"], 2)
        funct3 = _parse_field(row["funct3[2:0]"], 3)
        funct7 = _parse_field(row["funct7[6:0]"], 7)

        instr = build_instruction(opcode, funct3, funct7)
        dut.instruction.value = instr

        await Timer(1, units="ns")

        exp_selMuxPc4ALU    = _parse_field(row["SelMuxPc4ALU"], 1)
        exp_opExImm         = _parse_field(row["opExImm[2:0]"], 3)
        exp_selMuxALUPc4RAM = _parse_field(row["selMuxALUPc4RAM[1:0]"], 2)
        exp_weReg           = _parse_field(row["weReg"], 1)
        exp_opExRAM         = _parse_field(row["opExRAM[2:0]"], 3)
        exp_selMuxRS2Imm    = _parse_field(row["selMuxRS2Imm"], 1)
        exp_selPCRS1        = _parse_field(row["selMUXPcRS1"], 1)
        exp_opALU           = _parse_field(row["opALU[4:0]"], 5)
        exp_reRAM           = _parse_field(row["reRAM"], 1)
        exp_eRAM            = _parse_field(row["eRAM"], 1)
        exp_weRAM           = _parse_field(row["weRAM"], 1)

        got_selMuxPc4ALU    = int(dut.selMuxPc4ALU.value)
        got_opExImm         = int(dut.opExImm.value)
        got_selMuxALUPc4RAM = int(dut.selMuxALUPc4RAM.value)
        got_weReg           = int(dut.weReg.value)
        got_opExRAM         = int(dut.opExRAM.value)
        got_selMuxRS2Imm    = int(dut.selMuxRS2Imm.value)
        got_selPCRS1        = int(dut.selPCRS1.value)
        got_opALU           = int(dut.opALU.value)
        got_reRAM           = int(dut.reRAM.value)
        got_eRAM            = int(dut.eRAM.value)
        got_weRAM           = int(dut.weRAM.value)

        assert got_selMuxPc4ALU == exp_selMuxPc4ALU, (
            f"{inst_name}: selMuxPc4ALU got={got_selMuxPc4ALU} exp={exp_selMuxPc4ALU}"
        )
        assert got_opExImm == exp_opExImm, (
            f"{inst_name}: opExImm got={got_opExImm:03b} exp={exp_opExImm:03b}"
        )
        assert got_selMuxALUPc4RAM == exp_selMuxALUPc4RAM, (
            f"{inst_name}: selMuxALUPc4RAM got={got_selMuxALUPc4RAM:02b} exp={exp_selMuxALUPc4RAM:02b}"
        )
        assert got_weReg == exp_weReg, (
            f"{inst_name}: weReg got={got_weReg} exp={exp_weReg}"
        )
        assert got_opExRAM == exp_opExRAM, (
            f"{inst_name}: opExRAM got={got_opExRAM:03b} exp={exp_opExRAM:03b}"
        )
        assert got_selMuxRS2Imm == exp_selMuxRS2Imm, (
            f"{inst_name}: selMuxRS2Imm got={got_selMuxRS2Imm} exp={exp_selMuxRS2Imm}"
        )
        assert got_selPCRS1 == exp_selPCRS1, (
            f"{inst_name}: selPCRS1 got={got_selPCRS1} exp={exp_selPCRS1}"
        )
        assert got_opALU == exp_opALU, (
            f"{inst_name}: opALU got={got_opALU:05b} exp={exp_opALU:05b}"
        )
        assert got_reRAM == exp_reRAM, (
            f"{inst_name}: reRAM got={got_reRAM} exp={exp_reRAM}"
        )
        assert got_eRAM == exp_eRAM, (
            f"{inst_name}: eRAM got={got_eRAM} exp={exp_eRAM}"
        )
        assert got_weRAM == exp_weRAM, (
            f"{inst_name}: weRAM got={got_weRAM} exp={exp_weRAM}"
        )

        # Saidas novas do pipeline
        got_opCode = int(dut.opCode.value)
        got_funct3 = int(dut.funct3_out.value)
        assert got_opCode == opcode, (
            f"{inst_name}: opCode got={got_opCode:07b} exp={opcode:07b}"
        )
        assert got_funct3 == funct3, (
            f"{inst_name}: funct3_out got={got_funct3:03b} exp={funct3:03b}"
        )

        dut._log.info(f"{inst_name}: OK")


@cocotb.test()
async def test_control_unit_muldiv(dut):
    """
    Testa as 8 instrucoes da extensao M (R-type com funct7=0000001).
    isMulDiv deve estar '1' e weReg='1'.
    """
    m_instructions = [
        ("MUL",    0b000),
        ("MULH",   0b001),
        ("MULHSU", 0b010),
        ("MULHU",  0b011),
        ("DIV",    0b100),
        ("DIVU",   0b101),
        ("REM",    0b110),
        ("REMU",   0b111),
    ]

    for name, funct3 in m_instructions:
        instr = build_instruction(opcode=0b0110011, funct3=funct3, funct7=0b0000001)
        dut.instruction.value = instr
        await Timer(1, units="ns")

        got_isMulDiv = int(dut.isMulDiv.value)
        got_weReg    = int(dut.weReg.value)
        got_funct3   = int(dut.funct3_out.value)

        assert got_isMulDiv == 1, f"{name}: isMulDiv esperado 1, got {got_isMulDiv}"
        assert got_weReg == 1,    f"{name}: weReg esperado 1, got {got_weReg}"
        assert got_funct3 == funct3, (
            f"{name}: funct3_out got={got_funct3:03b} exp={funct3:03b}"
        )

        dut._log.info(f"{name}: isMulDiv=1 weReg=1 funct3={funct3:03b} OK")
