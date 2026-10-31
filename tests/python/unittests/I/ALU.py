import cocotb
from cocotb.triggers import Timer


OPCODES = {
    "ADD":    "00000",
    "SLL":    "00001",
    "XOR":    "00100",
    "SRL":    "00101",
    "OR":     "00110",
    "AND":    "00111",
    "SUB":    "01000",
    "SLT":    "01010",
    "SLTU":   "01011",
    "SRA":    "01101",
    "JALR":   "10000",
    "LUI":    "10001",
    "BEQ":    "11000",
    "BNE":    "11001",
    "BLT":    "11100",
    "BGE":    "11101",
    "BLTU":   "11110",
    "BGEU":   "11111"
}


def result_select(op_bits):
    """Seleção one-hot do resultado, como o estágio ID decodifica (alu_result_select)."""
    op = int(op_bits, 2)
    if op & 0b10000:
        return 0 if op & 0b01000 else 1  # desvios: nada; JALR e LUI: soma
    return 1 << (op & 0b111)  # 0 soma, 1 SLL, 2 SLT, 3 SLTU, 4 XOR, 5 deslocamento à direita, 6 OR, 7 AND


def to_bits(val, width=32):
    mask = (1 << width) - 1
    return val & mask


def to_signed(val, width=32):
    mask = (1 << width) - 1
    val &= mask
    if val & (1 << (width - 1)):
        return val - (1 << width)
    return val


async def apply_and_check(dut, op_name, a, b, expected_data, expected_branch):
    dut.i_op.value = int(OPCODES[op_name], 2)
    dut.i_res_sel.value = result_select(OPCODES[op_name])
    dut.i_a.value = to_bits(a)
    dut.i_b.value = to_bits(b)
    await Timer(1, units="ns")

    got_data = int(dut.o_d.value)
    got_branch = int(dut.o_branch.value)

    assert got_data == to_bits(expected_data), (
        f"{op_name}: dA={a}, dB={b}, "
        f"esperado dataOut={expected_data}, obtido {to_signed(got_data)} "
        f"(hex: dA={a:#010x}, dB={b:#010x}, dataOut={got_data:#010x}), "
        f"branch={got_branch}"
    )
    assert got_branch == expected_branch, (
        f"{op_name}: esperado branch={expected_branch}, obtido {got_branch}"
    )

    dut._log.info(
        f"{op_name} OK: "
        f"dA={a}, dB={b}, dataOut={to_signed(got_data)} "
        f"(hex: dA={a:#010x}, dB={b:#010x}, dataOut={got_data:#010x}), "
        f"branch={got_branch}"
    )


# === Testes separados para cada operação ===

@cocotb.test()
async def lui(dut):
    # LUI carrega o imediato de B, qualquer que seja o operando A
    for a, b in ((10, 20), (0xFFFFFFFF, 0x12345000), (0x80000000, 0)):
        await apply_and_check(dut, "LUI", a, b, b, 0)


@cocotb.test()
async def add(dut):
    a, b = 15, 7
    await apply_and_check(dut, "ADD", a, b, a + b, 0)


@cocotb.test()
async def sub(dut):
    a, b = 50, 20
    await apply_and_check(dut, "SUB", a, b, a - b, 0)


@cocotb.test()
async def xor(dut):
    a, b = 0b1010, 0b1100
    await apply_and_check(dut, "XOR", a, b, a ^ b, 0)


@cocotb.test()
async def or_(dut):
    a, b = 0b1010, 0b1100
    await apply_and_check(dut, "OR", a, b, a | b, 0)


@cocotb.test()
async def and_(dut):
    a, b = 0b1010, 0b1100
    await apply_and_check(dut, "AND", a, b, a & b, 0)


@cocotb.test()
async def sll(dut):
    a, b = 1, 3
    await apply_and_check(dut, "SLL", a, b, to_bits(a << (b & 0x1F)), 0)


@cocotb.test()
async def srl(dut):
    a, b = 16, 2
    await apply_and_check(dut, "SRL", a, b, a >> (b & 0x1F), 0)


@cocotb.test()
async def sra(dut):
    a, b = -16, 2
    await apply_and_check(dut, "SRA", a, b, to_signed(a) >> (b & 0x1F), 0)


@cocotb.test()
async def slt(dut):
    a, b = -5, 7
    await apply_and_check(dut, "SLT", a, b, 1 if to_signed(a) < to_signed(b) else 0, 0)


@cocotb.test()
async def sltu(dut):
    a, b = 5, 7
    await apply_and_check(dut, "SLTU", a, b, 1 if a < b else 0, 0)


@cocotb.test()
async def beq(dut):
    a, b = 10, 10
    await apply_and_check(dut, "BEQ", a, b, 0, 1)
    a, b = 10, 5
    await apply_and_check(dut, "BEQ", a, b, 0, 0)


@cocotb.test()
async def bne(dut):
    a, b = 10, 20
    await apply_and_check(dut, "BNE", a, b, 0, 1)


@cocotb.test()
async def blt(dut):
    a, b = -5, 7
    await apply_and_check(dut, "BLT", a, b, 0, 1)


@cocotb.test()
async def bge(dut):
    a, b = 10, 5
    await apply_and_check(dut, "BGE", a, b, 0, 1)


@cocotb.test()
async def bltu(dut):
    a, b = 1, 2
    await apply_and_check(dut, "BLTU", a, b, 0, 1)


@cocotb.test()
async def bgeu(dut):
    a, b = 2, 1
    await apply_and_check(dut, "BGEU", a, b, 0, 1)

    
@cocotb.test()
async def jalr(dut):
    """
    Testa JALR: target = (rs1 + imm) with least-significant bit cleared.
    Verifica dois casos: LSB já zero e LSB = 1 (deve ser forçado a 0).
    Espera branch = 1 (ajuste se seu ALU usar outro comportamento).
    """
    # caso 1: soma com LSB já zero
    a = 0x1003   # rs1
    b = 0x0005   # imm (exemplo)
    sum_res = (a + b) & ~1
    await apply_and_check(dut, "JALR", a, b, sum_res, 0)

    # caso 2: soma com LSB = 1 -> deve ficar com LSB = 0
    a = 0x1002
    b = 0x0001
    sum_res = (a + b) & ~1   # força bit 0 = 0
    await apply_and_check(dut, "JALR", a, b, sum_res, 0)

    dut._log.info("JALR tests OK")


def reference(op_name, a, b):
    """Resultado de dados e condição de desvio esperados para a operação."""
    sa, sb = to_signed(a), to_signed(b)
    sh = b & 0x1F
    data = {
        "ADD": a + b, "SUB": a - b, "XOR": a ^ b, "OR": a | b, "AND": a & b,
        "SLL": a << sh, "SRL": a >> sh, "SRA": sa >> sh,
        "SLT": int(sa < sb), "SLTU": int(a < b),
        "JALR": (a + b) & ~1, "LUI": b,
    }
    branch = {
        "BEQ": a == b, "BNE": a != b, "BLT": sa < sb, "BGE": sa >= sb,
        "BLTU": a < b, "BGEU": a >= b,
    }
    if op_name in branch:
        return 0, int(branch[op_name])
    return data[op_name], 0


@cocotb.test()
async def every_operation_against_the_reference(dut):
    """Cada operação confere com o modelo em valores de borda e aleatórios."""
    import random
    rng = random.Random(11)
    edges = [0, 1, 2, 31, 32, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, 0xFFFFFFFF]
    pairs = [(x, y) for x in edges for y in edges]
    pairs += [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(300)]
    pairs += [(v, v) for v in (0, 5, 0x80000000, 0xFFFFFFFF)]
    for op_name in OPCODES:
        for a, b in pairs:
            data, branch = reference(op_name, a, b)
            await apply_and_check(dut, op_name, a, b, data, branch)
