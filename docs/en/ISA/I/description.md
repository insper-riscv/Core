# RV32I: Core Implementation

This document describes how the Core implements the RV32I base integer set. The RISC-V manual requirements are in [instructions.md](instructions.md), and the full pipeline microarchitecture is in [ARCHITECTURE.md](../../ARCHITECTURE.md).

## 1. Base Modules

| Module | Folder | Responsibility |
| :--- | :--- | :--- |
| `alu` | `src/I/` | Integer operations, effective address, `JALR` target, and branch condition ([ALU.md](ALU.md)) |
| `extender_imm` | `src/I/` | Builds the 32-bit immediate of each format |
| `extender_ram` | `src/I/` | Selects and extends the byte or halfword read by a load |
| `store_manager` | `src/I/` | Positions the store data in the word and generates the byte mask |
| `control_unit` | `src/shared/` | Decodes `opcode`, `funct3`, and `funct7` into control signals ([DECODER.md](DECODER.md)) and detects illegal instructions |
| `reg_file` | `src/shared/` | Register file with two read ports and one write port |
| `pc_fetch` | `src/shared/` | `pc` register, $\text{pc} + 4$ sum, and next-`pc` selection |
| `forwarding_unit` and `hazard_detection_unit` | `src/shared/` | Operand forwarding and stall on load dependence |
| `stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb` | `src/core/` | The five pipeline stages |

## 2. Instruction Distribution across Stages

| Stage | What the RV32I base does |
| :--- | :--- |
| IF | Fetches the instruction at `pc` and picks the next `pc` among $\text{pc} + 4$, the branch or `JAL` target, the `JALR` target, and the trap redirect |
| ID | Decodes the control signals, extends the immediate, reads `rs1` and `rs2` from the register file, and detects the load dependence |
| EX | Applies forwarding to the operands, runs the ALU, computes $\text{pc} + \text{imm}$ in the branch adder, evaluates the branch condition, and formats the store data and byte mask |
| MEM | Sends the effective address, data, and mask to the right memory and waits for the response when the slave is slow |
| WB | Aligns and extends the word read by a load, chooses between it and the ALU result, and writes `rd` |

## 3. Control Unit

The control unit is combinational. Its signals start from defaults that form a `NOP` (no register write and no memory access), and each `opcode` overrides them. The full per-instruction table is in [DECODER.md](DECODER.md); the table below summarizes the role of the signals.

| Signal | Function |
| :--- | :--- |
| `o_sel_pc_rs1` | ALU operand A, `rs1` when `1` and `pc` when `0` (`AUIPC`, `JAL`, `LUI`) |
| `o_sel_rs2_imm` | ALU operand B, immediate when `1` and `rs2` when `0` |
| `o_sel_pc4_alu` | Selects $\text{pc} + 4$ as the EX result in `JAL` and `JALR` |
| `o_ext_imm_op` | Immediate format (U, I, I with `shamt`, S, B, or J) |
| `o_alu_op` | 5-bit ALU operation code |
| `o_we_reg` | Enables the write to `rd` |
| `o_wb_sel` | Source of the written data, ALU (`WB_SEL_ALU`) or memory (`WB_SEL_RAM`) |
| `o_re_ram`, `o_we_ram`, `o_en_ram` | Read, write, and enable of the data-memory access |
| `o_ext_ram_op` | Load width and extension (`LB`, `LH`, `LW`, `LBU`, `LHU`) |

A second process computes `o_illegal`. A word is legal when bits 1 and 0 are `11` and the combination of `opcode`, `funct3`, and `funct7` is one of those accepted in section 8 of [instructions.md](instructions.md). `FENCE` and the SYSTEM instructions are legal in this process, and the exception detector of the Zicsr extension later decides which SYSTEM instructions are valid.

## 4. Immediates

The immediate extender selects the format through `o_ext_imm_op`.

| Operation | 32-bit immediate |
| :--- | :--- |
| `EXT_IMM_U` | $\text{inst}[31{:}12] \,\Vert\, 0^{12}$ |
| `EXT_IMM_I` | $\text{sext}(\text{inst}[31{:}20])$ |
| `EXT_IMM_I_SHAMT` | $0^{27} \,\Vert\, \text{inst}[24{:}20]$ |
| `EXT_IMM_S` | $\text{sext}(\text{inst}[31{:}25] \,\Vert\, \text{inst}[11{:}7])$ |
| `EXT_IMM_B` | $\text{sext}(\text{inst}[31] \,\Vert\, \text{inst}[7] \,\Vert\, \text{inst}[30{:}25] \,\Vert\, \text{inst}[11{:}8] \,\Vert\, 0)$ |
| `EXT_IMM_J` | $\text{sext}(\text{inst}[31] \,\Vert\, \text{inst}[19{:}12] \,\Vert\, \text{inst}[20] \,\Vert\, \text{inst}[30{:}21] \,\Vert\, 0)$ |

Any other code produces zero. In SYSTEM instructions the ID stage forces the I format, because the exception detector reads the `funct12` field through the immediate.

## 5. Branches and Jumps

Branches and jumps resolve in EX, under the assume-not-taken policy.

| Instruction | Target | Condition |
| :--- | :--- | :--- |
| `JAL` | $\text{pc} + \text{imm}_J$, in the branch adder | Always taken |
| `JALR` | $(x[rs1] + \text{imm}_I) \land \texttt{0xFFFFFFFE}$, in the ALU | Always taken |
| `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` | $\text{pc} + \text{imm}_B$, in the branch adder | ALU `o_branch` |

`JAL` and `JALR` write $\text{pc} + 4$ to `rd` through the normal EX result path. When a branch or jump is taken, the IF/ID and ID/EX registers are discarded, which costs two cycles. The `pc` selector and its priority are in [ARCHITECTURE.md](../../ARCHITECTURE.md), section 2.3.

## 6. Data-Memory Access

The effective address $x[rs1] + \text{imm}$ leaves the ALU with the add operation. Its two low bits select the byte lane.

### 6.1. Stores

The store manager, in EX, replicates the data position and generates the byte mask. The mask is null when the instruction is not a store.

| Instruction | Data in the word | Byte mask per offset (0, 1, 2, 3) |
| :--- | :--- | :--- |
| `SW` | Whole $x[rs2]$ | `1111` for all |
| `SH` | $x[rs2][15{:}0]$ shifted by $8 \cdot \text{offset}$ bits (16 bits for offset 3) | `0011`, `0110`, `1100`, `1100` |
| `SB` | $x[rs2][7{:}0]$ shifted by $8 \cdot \text{offset}$ bits | `0001`, `0010`, `0100`, `1000` |

At offset 3 of `SH`, the access crosses the word and its handling is described in [MISALIGNED_ACCESS.md](../../MISALIGNED_ACCESS.md). The same holds for `SW` at an offset other than 0.

### 6.2. Loads

The load extender, in WB, receives the word read and the byte offset.

| Instruction | Result |
| :--- | :--- |
| `LW` | The whole word |
| `LH` | Halfword of the selected lane, sign-extended |
| `LHU` | Halfword of the selected lane, zero-extended |
| `LB` | Byte of the selected lane, sign-extended |
| `LBU` | Byte of the selected lane, zero-extended |

The final data of a load exists only at the end of WB. For this reason load forwarding starts from the WB2 register, and not from MEM/WB. Misaligned accesses, memory width, and the map regions have their own documents ([MISALIGNED_ACCESS.md](../../MISALIGNED_ACCESS.md) and [MEMORY_WIDTH.md](../../MEMORY_WIDTH.md)).

## 7. Register File

| Feature | Behavior |
| :--- | :--- |
| Ports | Two read ports (`rs1`, `rs2`) and one write port (`rd`) |
| `x0` | Constant zero, without a register; a write never enables it |
| Reset | Asynchronous, on registers `x1` to `x31` |
| Read in the write cycle | A multiplexer delivers the data being written when the register read is the same one, except `x0` |
| Size | 32 registers; the `num_regs` generic equal to 16 selects RV32E ([RV32E.md](../../RV32E.md)) |

## 8. Forwarding and Hazards

| Situation | Handling | Cost | Detail |
| :--- | :--- | :--- | :--- |
| Data dependence between nearby instructions | Forwarding to the EX operands from EX/MEM, MEM/WB, and WB2, with priority to the stage closest to EX; `x0` is never forwarded | None | [ARCHITECTURE.md](../../ARCHITECTURE.md), section 2.1 |
| Use of a load result | ID stall with a bubble in ID/EX | 2 cycles if the dependence is immediate, 1 if one instruction sits between them | [ARCHITECTURE.md](../../ARCHITECTURE.md), section 2.2 |
| Taken branch or jump | Discard of IF/ID and ID/EX | 2 cycles | [ARCHITECTURE.md](../../ARCHITECTURE.md), section 2.3 |
| Slow-memory wait | Global pipeline freeze | Wait time | [ARCHITECTURE.md](../../ARCHITECTURE.md), section 2.4 |

## 9. Generics That Affect the Base

| Generic | Effect on the RV32I base |
| :--- | :--- |
| `num_regs` | 32 or 16 registers; at 16, an instruction that uses `x16` to `x31` is illegal |
| `has_zicsr` | Enables the synchronous exception (illegal, `ECALL`, `EBREAK`, misaligned target) with redirect to `mtvec`; disabled, the Core only flags `o_trap` |
| `has_zicclsm` | Runs misaligned main-memory loads and stores in hardware; disabled, every misaligned access raises an exception |
| `has_zifencei` | Makes `FENCE.I` legal; `FENCE` is always legal |

## 10. Corner Cases

| Case | Behavior |
| :--- | :--- |
| Write with `rd` equal to `x0` | Discarded; forwarding ignores it |
| Load with `rd` equal to `x0` | The memory access and alignment check happen; the result is not written |
| `JALR` with target bit 0 set | Bit 0 is cleared before the target is used |
| Target with bit 1 set | Cause 0 exception with Zicsr; no check without Zicsr |
| Register shift | Uses only the 5 low bits of `rs2` |
| `SLLI`, `SRLI`, or `SRAI` with invalid `funct7` | Illegal instruction |
| `FENCE` with reserved fields | Executes as a `NOP` |
| Unknown word | `NOP` signals and `o_illegal` at `1` |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
