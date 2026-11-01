"""Testes de control unit."""

import csv
from pathlib import Path

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal, log_info


def _parse_field(val: str, _width: int) -> int:
    """Converta o campo da tabela para inteiro."""
    val = val.strip()
    if val == "-" or all(ch == "X" for ch in val):
        return 0

    symbol_map = {
        # campo opExImm, 3 bits
        "U": 0b000,
        "I": 0b001,
        "I_shamt": 0b010,
        "J": 0b011,
        "S": 0b100,
        "B": 0b101,
        # campo opExRAM, 3 bits
        "LW": 0b000,
        "LH": 0b001,
        "LHU": 0b010,
        "LB": 0b011,
        "LBU": 0b100,
        # campo opALU, 5 bits
        "ADD": 0b00000,
        "SLL": 0b00001,
        "XOR": 0b00100,
        "SRL": 0b00101,
        "OR": 0b00110,
        "AND": 0b00111,
        "SUB": 0b01000,
        "SLT": 0b01010,
        "SLTU": 0b01011,
        "SRA": 0b01101,
        "JALR": 0b10000,
        "LUI": 0b10001,
        "BEQ": 0b11000,
        "BNE": 0b11001,
        "BLT": 0b11100,
        "BGE": 0b11101,
        "BLTU": 0b11110,
        "BGEU": 0b11111,
    }

    if val in symbol_map:
        return symbol_map[val]

    return int(val, 2)


def load_reference():
    """Executa load reference.

    Carrega a tabela CSV de opcodes (mesma usada pelo
    InstructionDecoder).
    """
    data_dir = Path(__file__).resolve().parent / "data"
    csv_path = data_dir / "riscv_opcodes.csv"
    with Path(csv_path).open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def build_instruction(opcode: int, funct3: int, funct7: int) -> int:
    """Monta uma instrucao de 32 bits a partir dos campos.

    Layout R-type (suficiente para extrair opcode/funct3/funct7):
      [31:25]=funct7  [24:20]=rs2  [19:15]=rs1
      [14:12]=funct3  [11:7]=rd    [6:0]=opcode
    rs1, rs2, rd nao afetam a decisao do control_unit, ficam zero.
    """
    instr = 0
    instr |= opcode & 0x7F
    instr |= (funct3 & 0x7) << 12
    instr |= (funct7 & 0x7F) << 25
    return instr & 0xFFFFFFFF


# (rotulo, coluna do CSV, largura do campo, sinal do DUT, formato)
OUTPUT_CHECKS = (
    ("selMuxPc4ALU", "SelMuxPc4ALU", 1, "o_sel_pc4_alu", ""),
    ("opExImm", "opExImm[2:0]", 3, "o_ext_imm_op", "03b"),
    ("selMuxALURAM", "selMuxALURAM", 1, "o_wb_sel", "b"),
    ("weReg", "weReg", 1, "o_we_reg", ""),
    ("opExRAM", "opExRAM[2:0]", 3, "o_ext_ram_op", "03b"),
    ("selMuxRS2Imm", "selMuxRS2Imm", 1, "o_sel_rs2_imm", ""),
    ("selPCRS1", "selMUXPcRS1", 1, "o_sel_pc_rs1", ""),
    ("opALU", "opALU[4:0]", 5, "o_alu_op", "05b"),
    ("reRAM", "reRAM", 1, "o_re_ram", ""),
    ("eRAM", "eRAM", 1, "o_en_ram", ""),
    ("weRAM", "weRAM", 1, "o_we_ram", ""),
)


@cocotb.test()
async def test_control_unit(dut):
    """Verifica control unit.

    Para cada linha da tabela CSV: - monta a instrucao de 32 bits a
    partir de opcode/funct3/funct7 - aplica em dut.instruction - espera
    propagacao - compara todos os sinais de saida com a tabela -
    verifica que opCode e funct3_out (saidas novas) batem com a entrada
    """
    ref_table = load_reference()

    for row in ref_table:
        inst_name = row["INST"]
        opcode = int(row["OpCode[6:0]"], 2)
        funct3 = _parse_field(row["funct3[2:0]"], 3)
        funct7 = _parse_field(row["funct7[6:0]"], 7)

        instr = build_instruction(opcode, funct3, funct7)
        dut.i_inst.value = instr

        await Timer(1, unit="ns")

        for label, column, width, signal, fmt in OUTPUT_CHECKS:
            expected = _parse_field(row[column], width)
            got = int(getattr(dut, signal).value)
            check_equal(
                got,
                expected,
                f"{inst_name}: {label} got={got:{fmt}} exp={expected:{fmt}}",
            )

        # Saidas novas do pipeline
        got_op_code = int(dut.o_opcode.value)
        got_funct3 = int(dut.o_funct3.value)
        check_equal(
            got_op_code,
            opcode,
            f"{inst_name}: o_opcode got={got_op_code:07b} exp={opcode:07b}",
        )
        check_equal(
            got_funct3,
            funct3,
            f"{inst_name}: o_funct3 got={got_funct3:03b} exp={funct3:03b}",
        )

        log_info(f"{inst_name}: OK")


@cocotb.test()
async def test_control_unit_m_is_not_decoded_here(dut):
    """Verifica control unit m is not decoded here.

    O control_unit e' so' da base: as 8 instrucoes da extensao M (R-type
    com funct7=0000001) nao sobem o_we_reg aqui (quem as reivindica e'
    M/m_decode), mas o_funct3 segue a instrucao, porque a unidade M usa
    funct3 como operacao.
    """
    for funct3 in range(8):
        dut.i_inst.value = build_instruction(
            opcode=0b0110011, funct3=funct3, funct7=0b0000001
        )
        await Timer(1, unit="ns")

        check_equal(
            int(dut.o_we_reg.value),
            0,
            f"funct3={funct3:03b}: o_we_reg deveria ser 0",
        )
        got_funct3 = int(dut.o_funct3.value)
        check_equal(
            got_funct3,
            funct3,
            f"o_funct3 got={got_funct3:03b} exp={funct3:03b}",
        )


OPCODE_LOW_BITS = 0b11
OPCODE_OP_IMM = 0b0010011
OPCODE_OP = 0b0110011
FUNCT3_SLL = 1
FUNCT3_SRL_SRA = 5
FUNCT7_SUB_SRA = 0b0100000
# LUI, AUIPC, JAL and SYSTEM: any funct3 and funct7 is legal
OPCODES_ALWAYS_LEGAL = (0b0110111, 0b0010111, 0b1101111, 0b1110011)
# Legal funct3 per opcode: JALR, BRANCH, LOAD, STORE and MISC-MEM
LEGAL_FUNCT3 = {
    0b1100111: (0,),
    0b1100011: (0, 1, 4, 5, 6, 7),
    0b0000011: (0, 1, 2, 4, 5),
    0b0100011: (0, 1, 2),
    0b0001111: (0,),
}


def _legal_op_imm(funct3: int, funct7: int) -> bool:
    """Diga se o OP-IMM é válido; os deslocamentos fixam o funct7."""
    if funct3 == FUNCT3_SLL:
        return funct7 == 0
    if funct3 == FUNCT3_SRL_SRA:
        return funct7 in (0, FUNCT7_SUB_SRA)
    return True


def _legal_op(funct3: int, funct7: int) -> bool:
    """Diga se o OP é válido (funct7 = 1 é a extensão M)."""
    return funct7 == 0 or (funct7 == FUNCT7_SUB_SRA and funct3 in (0, 5))


def _legal(opcode: int, funct3: int, funct7: int) -> bool:
    """Diga se a codificação é uma instrução do RV32I.

    SYSTEM fica de fora, pois quem decide é a unidade de traps.
    """
    if opcode & OPCODE_LOW_BITS != OPCODE_LOW_BITS:
        return False
    if opcode in OPCODES_ALWAYS_LEGAL:
        return True
    if opcode == OPCODE_OP_IMM:
        return _legal_op_imm(funct3, funct7)
    if opcode == OPCODE_OP:
        return _legal_op(funct3, funct7)
    return funct3 in LEGAL_FUNCT3.get(opcode, ())


@cocotb.test()
async def test_illegal_flag(dut):
    """Verifica illegal flag.

    o_illegal marks exactly the encodings that RV32I does not define.
    """
    for opcode in range(128):
        for funct3 in range(8):
            for funct7 in (0, 1, 2, 0b0100000, 0b0100001, 0b1000000, 0x7F):
                dut.i_inst.value = build_instruction(opcode, funct3, funct7)
                await Timer(1, unit="ns")
                got = int(dut.o_illegal.value)
                want = int(not _legal(opcode, funct3, funct7))
                check_equal(
                    got,
                    want,
                    f"opcode={opcode:07b} funct3={funct3:03b} "
                    f"funct7={funct7:07b}: "
                    f"o_illegal got={got} exp={want}",
                )


@cocotb.test()
async def test_table_instructions_are_legal(dut):
    """Verifica table instructions are legal.

    Every instruction of the reference table is legal, but the NOP row
    (the all-zero word, which RISC-V defines as illegal).
    """
    for row in load_reference():
        if row["INST"] == "NOP":
            continue
        opcode = int(row["OpCode[6:0]"], 2)
        funct3 = _parse_field(row["funct3[2:0]"], 3)
        funct7 = _parse_field(row["funct7[6:0]"], 7)
        dut.i_inst.value = build_instruction(opcode, funct3, funct7)
        await Timer(1, unit="ns")
        check_equal(
            int(dut.o_illegal.value), 0, f"{row['INST']} is flagged illegal"
        )
