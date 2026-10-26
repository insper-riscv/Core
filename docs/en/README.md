# Incremental Implementation of the RV32I Base Instructions

This document describes the six basic 32-bit RISC-V instruction formats ([RISC-V green card](../instructions/greencardRISCV.pdf)) and the incremental datapath and control progression for the 37 base RV32I integer instructions.

## 1. RV32I Instruction Formats

| Format | Architectural purpose |
| :--- | :--- |
| **R-type** | Arithmetic, bitwise, shift, and comparison operations between two registers (`rs1` and `rs2`), writing the result to `rd` |
| **I-type** | Operations with a signed 12-bit immediate (`ADDI`..`ANDI`), 5-bit constant shifts (`SLLI`, `SRLI`, `SRAI`), memory loads (`LB`..`LW`), and indirect jump (`JALR`) |
| **S-type** | Byte, halfword, and word memory stores (`SB`, `SH`, `SW`) with a 12-bit offset split across fields `[31:25]` and `[11:7]` |
| **B-type** | PC-relative conditional branches (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) with a 2-byte aligned 13-bit offset |
| **U-type** | Loading a 20-bit upper immediate into bits `[31:12]` (`LUI`) or adding that upper immediate to the PC (`AUIPC`) |
| **J-type** | PC-relative unconditional jump (`JAL`) with a 2-byte aligned 21-bit offset, writing $\text{PC} + 4$ to `rd` |
| **SYSTEM / MISC-MEM** | Environment, CSR, and instruction-memory synchronization instructions (`ECALL`, `EBREAK`, `MRET`, `CSRR*`, `FENCE`, `FENCE.I`) |

### 1.1. General Format of the Types
![General format of the types](../instructions/types.webp)

### 1.2. Individual Format of the Instructions
![Individual format of the instructions](../instructions/individual.png)

## 2. Datapath Construction Order

The datapath construction divides the base RV32I instructions into six progressive groups:

1. **Group 1 (non-branching U-type):** `LUI` and `AUIPC` validate sequential fetch ($\text{PC} + 4$), `EXT_IMM_U` extension, ALU pass/add, and register-file writeback.
2. **Group 2 (arithmetic and logical I-type):** `ADDI`, `XORI`, `ORI`, `ANDI`, `SLTI`, `SLTIU`, `SLLI`, `SRLI`, and `SRAI` add reading `rs1`, `EXT_IMM_I` and `EXT_IMM_I_SHAMT` extensions, and shifters/comparators in the ALU.
3. **Group 3 (full R-type):** `ADD`, `SUB`, `XOR`, `OR`, `AND`, `SLL`, `SRL`, `SRA`, `SLT`, and `SLTU` introduce the second read port (`rs2`) and `o_sel_rs2_imm` selection between register and immediate.
4. **Group 4 (unconditional jumps):** `JAL` and `JALR` introduce writing $\text{PC} + 4$ into the link register (`WB_SEL_PC4`) and PC redirection (`PC_SRC_BRANCH` and `PC_SRC_JALR`).
5. **Group 5 (conditional branches):** `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, and `BGEU` add `EXT_IMM_B` extension and the ALU `o_branch` flag for conditional branching.
6. **Group 6 (loads and stores):** `LW`, `LH`, `LHU`, `LB`, `LBU`, `SW`, `SH`, and `SB` complete data-memory access with write alignment (`store_manager`) and read extension (`extender_ram`).

## 3. Breakdown of the Six Instruction Groups

### 3.1. Group 1: U-type (`LUI` and `AUIPC`)

| Instruction | `31:12 (imm)` | `11:7 (rd)` | `6:0 (opcode)` | Assembly | Semantics | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **LUI** | `imm[31:12]` | `rd` | `0110111` | `lui rd, imm` | `x[rd] = imm << 12` | Load upper immediate (U-type) |
| **AUIPC** | `imm[31:12]` | `rd` | `0010111` | `auipc rd, imm` | `x[rd] = pc + (imm << 12)` | Add upper immediate to PC (U-type) |

![Datapath Stage 1](../instructions/1.png)

- **Immediate extender (`extender_imm`):** `EXT_IMM_U` produces `i_instr[31:12] & x"000"`.
- **ALU (`alu`):** `ALU_PASS_B` (`o_d = i_b`) and `ALU_ADD` (`o_d = i_a + i_b`).
- **Control (`control_unit`):** asserts `o_we_reg = '1'` and `o_sel_rs2_imm = '1'`, selecting `o_sel_pc_rs1 = '0'` (PC) for `AUIPC`.

### 3.2. Group 2: Arithmetic and Logical I-type

| Instruction | `31:25` | `24:20` | `19:15 (rs1)` | `14:12 (funct3)` | `11:7 (rd)` | `6:0 (opcode)` | Assembly | Semantics | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **ADDI** | `imm[11:5]` | `imm[4:0]` | `rs1` | `000` | `rd` | `0010011` | `addi rd, rs1, imm` | `x[rd] = x[rs1] + sext(imm)` | Add immediate |
| **SLTI** | `imm[11:5]` | `imm[4:0]` | `rs1` | `010` | `rd` | `0010011` | `slti rd, rs1, imm` | `x[rd] = (x[rs1] <s sext(imm)) ? 1 : 0` | Set less than immediate (signed) |
| **SLTIU** | `imm[11:5]` | `imm[4:0]` | `rs1` | `011` | `rd` | `0010011` | `sltiu rd, rs1, imm` | `x[rd] = (x[rs1] <u sext(imm)) ? 1 : 0` | Set less than immediate (unsigned) |
| **XORI** | `imm[11:5]` | `imm[4:0]` | `rs1` | `100` | `rd` | `0010011` | `xori rd, rs1, imm` | `x[rd] = x[rs1] ^ sext(imm)` | Bitwise XOR immediate |
| **ORI** | `imm[11:5]` | `imm[4:0]` | `rs1` | `110` | `rd` | `0010011` | `ori rd, rs1, imm` | `x[rd] = x[rs1] \| sext(imm)` | Bitwise OR immediate |
| **ANDI** | `imm[11:5]` | `imm[4:0]` | `rs1` | `111` | `rd` | `0010011` | `andi rd, rs1, imm` | `x[rd] = x[rs1] & sext(imm)` | Bitwise AND immediate |
| **SLLI** | `0000000` | `shamt[4:0]` | `rs1` | `001` | `rd` | `0010011` | `slli rd, rs1, shamt` | `x[rd] = x[rs1] << shamt` | Shift left logical immediate |
| **SRLI** | `0000000` | `shamt[4:0]` | `rs1` | `101` | `rd` | `0010011` | `srli rd, rs1, shamt` | `x[rd] = x[rs1] >>u shamt` | Shift right logical immediate |
| **SRAI** | `0100000` | `shamt[4:0]` | `rs1` | `101` | `rd` | `0010011` | `srai rd, rs1, shamt` | `x[rd] = x[rs1] >>s shamt` | Shift right arithmetic immediate |

![Datapath Stage 2](../instructions/2.png)

- **Immediate extender:** `EXT_IMM_I` sign-extends `i_instr[31:20]`; `EXT_IMM_I_SHAMT` zero-extends `i_instr[24:20]`.
- **ALU:** adds `ALU_XOR`, `ALU_OR`, `ALU_AND`, `ALU_SLT`, `ALU_SLTU`, `ALU_SLL`, `ALU_SRL`, and `ALU_SRA` (`signed(i_a) >> unsigned(i_b[4:0])`).

### 3.3. Group 3: Full R-type

| Instruction | `31:25 (funct7)` | `24:20 (rs2)` | `19:15 (rs1)` | `14:12 (funct3)` | `11:7 (rd)` | `6:0 (opcode)` | Assembly | Semantics | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **ADD** | `0000000` | `rs2` | `rs1` | `000` | `rd` | `0110011` | `add rd, rs1, rs2` | `x[rd] = x[rs1] + x[rs2]` | Register addition |
| **SUB** | `0100000` | `rs2` | `rs1` | `000` | `rd` | `0110011` | `sub rd, rs1, rs2` | `x[rd] = x[rs1] - x[rs2]` | Register subtraction |
| **SLL** | `0000000` | `rs2` | `rs1` | `001` | `rd` | `0110011` | `sll rd, rs1, rs2` | `x[rd] = x[rs1] << x[rs2][4:0]` | Shift left logical |
| **SLT** | `0000000` | `rs2` | `rs1` | `010` | `rd` | `0110011` | `slt rd, rs1, rs2` | `x[rd] = (x[rs1] <s x[rs2]) ? 1 : 0` | Set less than (signed) |
| **SLTU** | `0000000` | `rs2` | `rs1` | `011` | `rd` | `0110011` | `sltu rd, rs1, rs2` | `x[rd] = (x[rs1] <u x[rs2]) ? 1 : 0` | Set less than (unsigned) |
| **XOR** | `0000000` | `rs2` | `rs1` | `100` | `rd` | `0110011` | `xor rd, rs1, rs2` | `x[rd] = x[rs1] ^ x[rs2]` | Bitwise XOR |
| **SRL** | `0000000` | `rs2` | `rs1` | `101` | `rd` | `0110011` | `srl rd, rs1, rs2` | `x[rd] = x[rs1] >>u x[rs2][4:0]` | Shift right logical |
| **SRA** | `0100000` | `rs2` | `rs1` | `101` | `rd` | `0110011` | `sra rd, rs1, rs2` | `x[rd] = x[rs1] >>s x[rs2][4:0]` | Shift right arithmetic |
| **OR** | `0000000` | `rs2` | `rs1` | `110` | `rd` | `0110011` | `or rd, rs1, rs2` | `x[rd] = x[rs1] \| x[rs2]` | Bitwise OR |
| **AND** | `0000000` | `rs2` | `rs1` | `111` | `rd` | `0110011` | `and rd, rs1, rs2` | `x[rd] = x[rs1] & x[rs2]` | Bitwise AND |

![Datapath Stage 3](../instructions/3.png)

- **ALU:** adds `ALU_SUB` (`o_d = i_a - i_b`).
- **Control:** keeps `o_sel_pc_rs1 = '1'` (`rs1`) and `o_sel_rs2_imm = '0'` (`rs2`) only when `funct7` equals `FUNCT7_DEFAULT` (`"0000000"`) or `FUNCT7_ALT` (`"0100000"`).

### 3.4. Group 4: Unconditional Jumps (`JAL` and `JALR`)

| Instruction | `31:25` | `24:20` | `19:15` | `14:12` | `11:7 (rd)` | `6:0 (opcode)` | Assembly | Semantics | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **JAL** | `imm[20\|10:5]` | `imm[4:1\|11]` | `imm[19:15]` | `imm[14:12]` | `rd` | `1101111` | `jal rd, off` | `x[rd] = pc + 4; pc = pc + sext(off)` | PC-relative jump (J-type) |
| **JALR** | `imm[11:5]` | `imm[4:0]` | `rs1` | `000` | `rd` | `1100111` | `jalr rd, rs1, off` | `t = pc + 4; pc = (x[rs1] + sext(off)) & ~1; x[rd] = t` | Indirect jump via `rs1` (I-type) |

![Datapath Stage 4](../instructions/4.png)

- **Immediate extender:** `EXT_IMM_J` for `JAL` and `EXT_IMM_I` for `JALR`.
- **ALU and Control:** `o_sel_pc4_alu = '1'` and `o_wb_sel = WB_SEL_PC4` select $\text{PC} + 4$ as the return address written to `rd`, while `ALU_JALR` computes the `JALR` target address with bit 0 cleared.

### 3.5. Group 5: Conditional Branches (`BRANCH`)

| Instruction | `31:25` | `24:20 (rs2)` | `19:15 (rs1)` | `14:12 (funct3)` | `11:7` | `6:0 (opcode)` | Assembly | Semantics | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **BEQ** | `imm[12\|10:5]` | `rs2` | `rs1` | `000` | `imm[4:1\|11]` | `1100011` | `beq rs1, rs2, off` | `if (x[rs1] == x[rs2]) pc += sext(off)` | Branch if equal |
| **BNE** | `imm[12\|10:5]` | `rs2` | `rs1` | `001` | `imm[4:1\|11]` | `1100011` | `bne rs1, rs2, off` | `if (x[rs1] != x[rs2]) pc += sext(off)` | Branch if not equal |
| **BLT** | `imm[12\|10:5]` | `rs2` | `rs1` | `100` | `imm[4:1\|11]` | `1100011` | `blt rs1, rs2, off` | `if (x[rs1] <s x[rs2]) pc += sext(off)` | Branch if less than (signed) |
| **BGE** | `imm[12\|10:5]` | `rs2` | `rs1` | `101` | `imm[4:1\|11]` | `1100011` | `bge rs1, rs2, off` | `if (x[rs1] >=s x[rs2]) pc += sext(off)` | Branch if greater or equal (signed) |
| **BLTU** | `imm[12\|10:5]` | `rs2` | `rs1` | `110` | `imm[4:1\|11]` | `1100011` | `bltu rs1, rs2, off` | `if (x[rs1] <u x[rs2]) pc += sext(off)` | Branch if less than (unsigned) |
| **BGEU** | `imm[12\|10:5]` | `rs2` | `rs1` | `111` | `imm[4:1\|11]` | `1100011` | `bgeu rs1, rs2, off` | `if (x[rs1] >=u x[rs2]) pc += sext(off)` | Branch if greater or equal (unsigned) |

![Datapath Stage 5](../instructions/5.png)

- **Immediate extender:** `EXT_IMM_B` reconstructs the signed 13-bit branch offset.
- **ALU and Branch Target:** the ALU compares `rs1` and `rs2` (`ALU_BEQ`..`ALU_BGEU`) driving `o_branch`, while the dedicated adder `u_branch_target_adder` in the EX stage computes $\text{PC} + \text{imm}$.

### 3.6. Group 6: Memory Access (`LOAD` and `STORE`)

| Instruction | `31:25` | `24:20` | `19:15 (rs1)` | `14:12 (funct3)` | `11:7` | `6:0 (opcode)` | Assembly | Semantics | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **LW** | `imm[11:5]` | `imm[4:0]` | `rs1` | `010` | `rd` | `0000011` | `lw rd, off(rs1)` | `x[rd] = M[x[rs1] + sext(off)][31:0]` | Load word (32 bits) |
| **LH** | `imm[11:5]` | `imm[4:0]` | `rs1` | `001` | `rd` | `0000011` | `lh rd, off(rs1)` | `x[rd] = sext(M[x[rs1] + sext(off)][15:0])` | Load halfword (signed) |
| **LHU** | `imm[11:5]` | `imm[4:0]` | `rs1` | `101` | `rd` | `0000011` | `lhu rd, off(rs1)` | `x[rd] = zext(M[x[rs1] + sext(off)][15:0])` | Load halfword (unsigned) |
| **LB** | `imm[11:5]` | `imm[4:0]` | `rs1` | `000` | `rd` | `0000011` | `lb rd, off(rs1)` | `x[rd] = sext(M[x[rs1] + sext(off)][7:0])` | Load byte (signed) |
| **LBU** | `imm[11:5]` | `imm[4:0]` | `rs1` | `100` | `rd` | `0000011` | `lbu rd, off(rs1)` | `x[rd] = zext(M[x[rs1] + sext(off)][7:0])` | Load byte (unsigned) |
| **SW** | `imm[11:5]` | `rs2` | `rs1` | `010` | `imm[4:0]` | `0100011` | `sw rs2, off(rs1)` | `M[x[rs1] + sext(off)][31:0] = x[rs2][31:0]` | Store word (32 bits) |
| **SH** | `imm[11:5]` | `rs2` | `rs1` | `001` | `imm[4:0]` | `0100011` | `sh rs2, off(rs1)` | `M[x[rs1] + sext(off)][15:0] = x[rs2][15:0]` | Store halfword (16 bits) |
| **SB** | `imm[11:5]` | `rs2` | `rs1` | `000` | `imm[4:0]` | `0100011` | `sb rs2, off(rs1)` | `M[x[rs1] + sext(off)][7:0] = x[rs2][7:0]` | Store byte (8 bits) |

![Datapath Stage 6](../instructions/6.png)

- **Effective address calculation:** `ALU_ADD` adds `rs1` to the `EXT_IMM_I` (loads) or `EXT_IMM_S` (stores) immediate.
- **Store alignment (`store_manager` in the EX stage):** positions `rs2` into the byte lanes selected by `ea[1:0]` and drives `o_byte_mask`.
- **Load extension (`extender_ram` in the WB stage):** selects the byte or halfword indicated by `ea[1:0]` and extends it according to `o_ext_ram_op` (`EXT_RAM_LW`, `EXT_RAM_LH`, `EXT_RAM_LHU`, `EXT_RAM_LB`, `EXT_RAM_LBU`), writing the result back via `WB_SEL_RAM`.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../LICENSE).
