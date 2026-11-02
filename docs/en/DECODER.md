# Base Control Unit Decoding Table (RV32I)

The base control unit (`src/shared/control_unit.vhd`) combinationally decodes the `opcode` (`i_inst[6:0]`), `funct3` (`i_inst[14:12]`), and `funct7` (`i_inst[31:25]`) fields of the 37 RV32I instructions. Any instruction outside this table (including instructions from the `M`, `Zicsr`, and `Zifencei` extensions) receives the default side-effect-free `NOP` control word in this unit (`o_we_reg = '0'`, `o_we_ram = '0'`, `o_re_ram = '0'`, `o_en_ram = '0'`).

## 1. Control Signals per Instruction

| Instruction | Architectural semantics | `opcode` | `funct3` | `funct7` | `o_sel_pc4_alu` | `o_ext_imm_op` | `o_wb_sel` | `o_we_reg` | `o_ext_ram_op` | `o_sel_rs2_imm` | `o_sel_pc_rs1` | `o_alu_op` | `o_re_ram` | `o_we_ram` | `o_en_ram` |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `LUI` | `x[rd] = imm_u` | `0110111` | `-` | `-` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `0` | `ALU_LUI` | `0` | `0` | `0` |
| `AUIPC` | `x[rd] = pc + imm_u` | `0010111` | `-` | `-` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `0` | `ALU_ADD` | `0` | `0` | `0` |
| `ADDI` | `x[rd] = x[rs1] + sext(imm)` | `0010011` | `000` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_ADD` | `0` | `0` | `0` |
| `SLTI` | `x[rd] = (x[rs1] <s sext(imm)) ? 1 : 0` | `0010011` | `010` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_SLT` | `0` | `0` | `0` |
| `SLTIU` | `x[rd] = (x[rs1] <u sext(imm)) ? 1 : 0` | `0010011` | `011` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_SLTU` | `0` | `0` | `0` |
| `XORI` | `x[rd] = x[rs1] ^ sext(imm)` | `0010011` | `100` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_XOR` | `0` | `0` | `0` |
| `ORI` | `x[rd] = x[rs1] \| sext(imm)` | `0010011` | `110` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_OR` | `0` | `0` | `0` |
| `ANDI` | `x[rd] = x[rs1] & sext(imm)` | `0010011` | `111` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_AND` | `0` | `0` | `0` |
| `SLLI` | `x[rd] = x[rs1] << shamt` | `0010011` | `001` | `0000000` | `0` | `EXT_IMM_I_SHAMT` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_SLL` | `0` | `0` | `0` |
| `SRLI` | `x[rd] = x[rs1] >>u shamt` | `0010011` | `101` | `0000000` | `0` | `EXT_IMM_I_SHAMT` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_SRL` | `0` | `0` | `0` |
| `SRAI` | `x[rd] = x[rs1] >>s shamt` | `0010011` | `101` | `0100000` | `0` | `EXT_IMM_I_SHAMT` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_SRA` | `0` | `0` | `0` |
| `ADD` | `x[rd] = x[rs1] + x[rs2]` | `0110011` | `000` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_ADD` | `0` | `0` | `0` |
| `SUB` | `x[rd] = x[rs1] - x[rs2]` | `0110011` | `000` | `0100000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_SUB` | `0` | `0` | `0` |
| `SLL` | `x[rd] = x[rs1] << x[rs2][4:0]` | `0110011` | `001` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_SLL` | `0` | `0` | `0` |
| `SLT` | `x[rd] = (x[rs1] <s x[rs2]) ? 1 : 0` | `0110011` | `010` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_SLT` | `0` | `0` | `0` |
| `SLTU` | `x[rd] = (x[rs1] <u x[rs2]) ? 1 : 0` | `0110011` | `011` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_SLTU` | `0` | `0` | `0` |
| `XOR` | `x[rd] = x[rs1] ^ x[rs2]` | `0110011` | `100` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_XOR` | `0` | `0` | `0` |
| `SRL` | `x[rd] = x[rs1] >>u x[rs2][4:0]` | `0110011` | `101` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_SRL` | `0` | `0` | `0` |
| `SRA` | `x[rd] = x[rs1] >>s x[rs2][4:0]` | `0110011` | `101` | `0100000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_SRA` | `0` | `0` | `0` |
| `OR` | `x[rd] = x[rs1] \| x[rs2]` | `0110011` | `110` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_OR` | `0` | `0` | `0` |
| `AND` | `x[rd] = x[rs1] & x[rs2]` | `0110011` | `111` | `0000000` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `0` | `1` | `ALU_AND` | `0` | `0` | `0` |
| `JAL` | `x[rd] = pc + 4; pc = pc + imm_j` | `1101111` | `-` | `-` | `1` | `EXT_IMM_J` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `0` | `ALU_ADD` | `0` | `0` | `0` |
| `JALR` | `t = pc + 4; pc = (x[rs1] + imm_i) & ~1; x[rd] = t` | `1100111` | `000` | `-` | `1` | `EXT_IMM_I` | `WB_SEL_ALU` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_JALR` | `0` | `0` | `0` |
| `BEQ` | `if (x[rs1] == x[rs2]) pc += imm_b` | `1100011` | `000` | `-` | `0` | `EXT_IMM_B` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `0` | `1` | `ALU_BEQ` | `0` | `0` | `0` |
| `BNE` | `if (x[rs1] != x[rs2]) pc += imm_b` | `1100011` | `001` | `-` | `0` | `EXT_IMM_B` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `0` | `1` | `ALU_BNE` | `0` | `0` | `0` |
| `BLT` | `if (x[rs1] <s x[rs2]) pc += imm_b` | `1100011` | `100` | `-` | `0` | `EXT_IMM_B` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `0` | `1` | `ALU_BLT` | `0` | `0` | `0` |
| `BGE` | `if (x[rs1] >=s x[rs2]) pc += imm_b` | `1100011` | `101` | `-` | `0` | `EXT_IMM_B` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `0` | `1` | `ALU_BGE` | `0` | `0` | `0` |
| `BLTU` | `if (x[rs1] <u x[rs2]) pc += imm_b` | `1100011` | `110` | `-` | `0` | `EXT_IMM_B` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `0` | `1` | `ALU_BLTU` | `0` | `0` | `0` |
| `BGEU` | `if (x[rs1] >=u x[rs2]) pc += imm_b` | `1100011` | `111` | `-` | `0` | `EXT_IMM_B` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `0` | `1` | `ALU_BGEU` | `0` | `0` | `0` |
| `LB` | `x[rd] = sext(M[x[rs1] + imm_i][7:0])` | `0000011` | `000` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_RAM` | `1` | `EXT_RAM_LB` | `1` | `1` | `ALU_ADD` | `1` | `0` | `1` |
| `LH` | `x[rd] = sext(M[x[rs1] + imm_i][15:0])` | `0000011` | `001` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_RAM` | `1` | `EXT_RAM_LH` | `1` | `1` | `ALU_ADD` | `1` | `0` | `1` |
| `LW` | `x[rd] = M[x[rs1] + imm_i][31:0]` | `0000011` | `010` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_RAM` | `1` | `EXT_RAM_LW` | `1` | `1` | `ALU_ADD` | `1` | `0` | `1` |
| `LBU` | `x[rd] = zext(M[x[rs1] + imm_i][7:0])` | `0000011` | `100` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_RAM` | `1` | `EXT_RAM_LBU` | `1` | `1` | `ALU_ADD` | `1` | `0` | `1` |
| `LHU` | `x[rd] = zext(M[x[rs1] + imm_i][15:0])` | `0000011` | `101` | `-` | `0` | `EXT_IMM_I` | `WB_SEL_RAM` | `1` | `EXT_RAM_LHU` | `1` | `1` | `ALU_ADD` | `1` | `0` | `1` |
| `SB` | `M[x[rs1] + imm_s][7:0] = x[rs2][7:0]` | `0100011` | `000` | `-` | `0` | `EXT_IMM_S` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `1` | `1` | `ALU_ADD` | `0` | `1` | `1` |
| `SH` | `M[x[rs1] + imm_s][15:0] = x[rs2][15:0]` | `0100011` | `001` | `-` | `0` | `EXT_IMM_S` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `1` | `1` | `ALU_ADD` | `0` | `1` | `1` |
| `SW` | `M[x[rs1] + imm_s][31:0] = x[rs2][31:0]` | `0100011` | `010` | `-` | `0` | `EXT_IMM_S` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `1` | `1` | `ALU_ADD` | `0` | `1` | `1` |
| `NOP` / others | No operation in base RV32I | others | `-` | `-` | `0` | `EXT_IMM_U` | `WB_SEL_ALU` | `0` | `EXT_RAM_LW` | `0` | `0` | `ALU_ADD` | `0` | `0` | `0` |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../LICENSE).
