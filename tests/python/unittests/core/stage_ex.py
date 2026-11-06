"""Testes de stage_ex: estágio EX do pipeline, sem extensões.

Cobre a malha de forwarding, os multiplexadores de operandos, a ULA, o
resultado final, os alvos e as decisões de desvio, o dado de store e a
exceção síncrona do estágio quando não há Zicsr.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import Prng, check_equal

MASK32 = 0xFFFFFFFF
OP_BRANCH, OP_JAL, OP_JALR = 0b1100011, 0b1101111, 0b1100111
OP_LOAD, OP_STORE, OP_OP = 0b0000011, 0b0100011, 0b0110011
ALU = {
    "ADD": 0b00000,
    "XOR": 0b00100,
    "OR": 0b00110,
    "AND": 0b00111,
    "SUB": 0b01000,
    "SLT": 0b01010,
    "SLTU": 0b01011,
}
BRANCH = {
    "BEQ": 0b11000,
    "BNE": 0b11001,
    "BLT": 0b11100,
    "BGE": 0b11101,
    "BLTU": 0b11110,
    "BGEU": 0b11111,
}
IDLE = {
    "base_run": 1,
    "pipe_run": 1,
    "valid": 1,
    "valid_raw": 1,
    "pc": 0x100,
    "pc4": 0x104,
    "rs1_idx": 1,
    "rd_idx": 2,
    "rs1_val": 0,
    "rs2_val": 0,
    "imm": 0,
    "sel_pc4_alu": 0,
    "sel_rs2_imm": 0,
    "sel_pc_rs1": 1,
    "alu_op": ALU["ADD"],
    "alu_sel": 1,
    "is_muldiv": 0,
    "is_csr": 0,
    "illegal": 0,
    "opcode": OP_OP,
    "funct3": 0,
    "fwd_match_rs1": 0,
    "fwd_match_rs2": 0,
    "exmem_ok": 0,
    "memwb_ok": 0,
    "wb2_ok": 0,
    "exmem_alu_out": 0,
    "memwb_alu_out": 0,
    "wb2_data": 0,
    "dc_done": 0,
}
OUTPUTS = (
    "final_result",
    "store_data",
    "store_byte_mask",
    "branch_taken",
    "jalr_taken",
    "branch_target",
    "jalr_target",
    "trap_take",
    "trap_sig",
    "trap_sig_cause",
    "trap_sig_pc",
    "mret_take",
    "fencei_take",
    "muldiv_stall",
)


def result_select(op):
    """Seleção one-hot do resultado da ULA (alu_result_select)."""
    if op & 0b10000:
        return 0 if op & 0b01000 else 1
    return 1 << (op & 0b111)


def signed(value):
    """Interpreta uma palavra de 32 bits com sinal."""
    return value - (1 << 32) if value >> 31 else value


def alu_model(op, a, b):
    """Modelo de referência da ULA para as operações exercitadas."""
    results = {
        ALU["ADD"]: a + b,
        ALU["SUB"]: a - b,
        ALU["XOR"]: a ^ b,
        ALU["OR"]: a | b,
        ALU["AND"]: a & b,
        ALU["SLT"]: int(signed(a) < signed(b)),
        ALU["SLTU"]: int(a < b),
    }
    return results[op] & MASK32


def branch_model(op, a, b):
    """Modelo da condição de desvio da ULA."""
    return int(
        {
            BRANCH["BEQ"]: a == b,
            BRANCH["BNE"]: a != b,
            BRANCH["BLT"]: signed(a) < signed(b),
            BRANCH["BGE"]: signed(a) >= signed(b),
            BRANCH["BLTU"]: a < b,
            BRANCH["BGEU"]: a >= b,
        }[op]
    )


def forward_model(match, oks, sources):
    """Fonte mais nova que casa e é válida (EX/MEM, MEM/WB, WB2).

    As fontes vêm como (rs, memwb, exmem, wb2) e a primeira é o valor
    do banco de registradores.
    """
    for bit, source in ((0, 2), (1, 1), (2, 3)):
        if (match >> bit) & 1 and oks[bit]:
            return sources[source]
    return sources[0]


async def run(dut, values):
    """Aplica as entradas (sobre IDLE) e devolve as saídas."""
    for name, value in (IDLE | values).items():
        getattr(dut, f"i_{name}").value = value
    dut.i_rst.value = 0
    dut.i_clk.value = 0
    await Timer(1, unit="ns")
    return {name: int(getattr(dut, f"o_{name}").value) for name in OUTPUTS}


def random_operands(prng):
    """Sorteia as entradas do teste de forwarding e dos muxes."""
    values = {
        name: prng.getrandbits(32)
        for name in (
            "rs1_val",
            "rs2_val",
            "imm",
            "pc",
            "exmem_alu_out",
            "memwb_alu_out",
            "wb2_data",
        )
    }
    for name in ("fwd_match_rs1", "fwd_match_rs2"):
        values[name] = prng.getrandbits(3)
    for name in ("exmem_ok", "memwb_ok", "wb2_ok"):
        values[name] = prng.getrandbits(1)
    for name in ("sel_pc_rs1", "sel_rs2_imm"):
        values[name] = prng.getrandbits(1)
    values["alu_op"] = prng.choice(list(ALU.values()))
    values["alu_sel"] = result_select(values["alu_op"])
    return values


def operand_model(values):
    """Devolve os operandos A e B da ULA depois de forwarding e mux."""
    oks = (values["exmem_ok"], values["memwb_ok"], values["wb2_ok"])
    sources = (values["memwb_alu_out"], values["exmem_alu_out"])
    sources += (values["wb2_data"],)
    fwd_a = forward_model(
        values["fwd_match_rs1"], oks, (values["rs1_val"], *sources)
    )
    fwd_b = forward_model(
        values["fwd_match_rs2"], oks, (values["rs2_val"], *sources)
    )
    op_a = fwd_a if values["sel_pc_rs1"] else values["pc"]
    op_b = values["imm"] if values["sel_rs2_imm"] else fwd_b
    return op_a, op_b


@cocotb.test()
async def test_forwarding_and_operand_muxes(dut):
    """Forwarding e multiplexadores alimentam a ULA com os operandos."""
    prng = Prng(0xE1)
    for index in range(300):
        values = random_operands(prng)
        seen = await run(dut, values)
        op_a, op_b = operand_model(values)
        want = alu_model(values["alu_op"], op_a, op_b)
        check_equal(seen["final_result"], want, (index, values["alu_op"]))


@cocotb.test()
async def test_final_result_selects_pc4(dut):
    """JAL e JALR gravam PC + 4 no lugar do resultado da ULA."""
    seen = await run(dut, {"rs1_val": 5, "imm": 7, "sel_pc4_alu": 1})
    check_equal(seen["final_result"], 0x104, "PC + 4")
    seen = await run(dut, {"rs1_val": 5, "imm": 7, "sel_rs2_imm": 1})
    check_equal(seen["final_result"], 12, "ULA")


@cocotb.test()
async def test_branch_decisions_and_targets(dut):
    """Desvios, JAL e JALR: decisão, alvos e efeito da validade."""
    prng = Prng(0xB4)
    for index in range(200):
        a, b, imm, pc = (prng.getrandbits(32) for _ in range(4))
        a, b = (a, a) if index % 4 == 0 else (a, b)
        op = prng.choice(list(BRANCH.values()))
        valid = int(index % 5 != 0)
        base = {"rs1_val": a, "rs2_val": b, "imm": imm, "pc": pc}
        base |= {"alu_op": op, "alu_sel": result_select(op), "valid": valid}
        seen = await run(dut, base | {"opcode": OP_BRANCH})
        want = valid & branch_model(op, a, b)
        check_equal(seen["branch_taken"], want, (index, op))
        check_equal(seen["branch_target"], (pc + imm) & MASK32, index)
        check_equal(seen["jalr_taken"], 0, index)
        seen = await run(dut, base | {"opcode": OP_JAL})
        check_equal(seen["branch_taken"], valid, (index, "jal"))
        seen = await run(
            dut, base | {"opcode": OP_JALR, "alu_op": 0, "alu_sel": 1}
        )
        check_equal(seen["jalr_taken"], valid, (index, "jalr"))
        check_equal(seen["branch_taken"], 0, (index, "jalr"))
        check_equal(
            seen["jalr_target"], (a + b) & MASK32, (index, "jalr alvo")
        )


@cocotb.test()
async def test_store_data_uses_forwarded_rs2(dut):
    """O dado e a máscara do store vêm do rs2 depois do forwarding."""
    base = {"opcode": OP_STORE, "sel_rs2_imm": 1, "imm": 0}
    base |= {"rs1_val": 0x1000, "rs2_val": 0x11223344}
    seen = await run(dut, base | {"funct3": 0b010})
    check_equal(
        (seen["store_data"], seen["store_byte_mask"]), (0x11223344, 0xF), "SW"
    )
    seen = await run(dut, base | {"funct3": 0b000, "imm": 3})
    check_equal(
        (seen["store_data"], seen["store_byte_mask"]),
        (0x44000000, 0b1000),
        "SB no byte 3",
    )
    forwarded = {"fwd_match_rs2": 0b001, "exmem_ok": 1}
    forwarded |= {"exmem_alu_out": 0xAABBCCDD, "funct3": 0b010}
    seen = await run(dut, base | forwarded)
    check_equal(seen["store_data"], 0xAABBCCDD, "SW com forwarding")


@cocotb.test()
async def test_synchronous_exception_without_zicsr(dut):
    """Sem Zicsr a exceção sai pelo sinal de trap do estágio."""
    seen = await run(dut, {"illegal": 1})
    check_equal((seen["trap_sig"], seen["trap_sig_cause"]), (1, 2), "ilegal")
    check_equal(seen["trap_sig_pc"], 0x100, "PC da exceção")
    check_equal(seen["trap_take"], 0, "sem CSR não há trap interno")
    for gate in ("valid", "pipe_run"):
        seen = await run(dut, {"illegal": 1, gate: 0})
        check_equal(seen["trap_sig"], 0, gate)
    seen = await run(
        dut,
        {"opcode": OP_LOAD, "funct3": 0b010, "imm": 0x1001}
        | {"sel_rs2_imm": 1},
    )
    check_equal((seen["trap_sig"], seen["trap_sig_cause"]), (1, 4), "LW")
