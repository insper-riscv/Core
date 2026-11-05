# RV32I: ISA Requirements and Core Behavior

Chapter 1 of the manual ([RV32I Base Integer Instruction Set](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)).

This document gathers what the RISC-V manual requires of the RV32I base integer set and, at each point, what the Core does. The source is the unprivileged ISA manual, version 20260120, Chapter 1 ("RV32I Base Integer Instruction Set, Version 2.1"), section 1.1 and its subsections. The encodings match the instruction listing in Chapter 35 of the same manual. The text paraphrases the manual and does not replace it. The hardware implementation is in [description.md](description.md).

## 1. Programmer State

Manual section 1.1.1.

| Element | Width | Manual rule |
| :--- | :--- | :--- |
| `x0` | 32 bits | Hardwired to zero; reads return 0 and writes have no effect |
| `x1` to `x31` | 32 bits | General-purpose registers |
| `pc` | 32 bits | Address of the executing instruction; it is the only other unprivileged register |

The manual defines no stack pointer or link register; the convention uses `x1` as the return address, `x5` as an alternate link register, and `x2` as the stack pointer. The RV32E variant reduces the file to 16 registers (manual Chapter 2) and is covered in [RV32E.md](../E/description.md).

In the Core, `x0` has no flip-flop. The register file stores only `x1` to `x31`, and the read port returns the constant zero for address 0. A write to `x0` is discarded, and data forwarding ignores any instruction whose destination is `x0`.

## 2. Instruction Formats

Manual sections 1.1.2 and 1.1.3. Every instruction is 32 bits wide, and the `rs1`, `rs2`, and `rd` fields sit in the same positions in all formats. The sign bit of every immediate is instruction bit 31.

| Format | Fields (bit 31 down to bit 0) | Immediate produced |
| :--- | :--- | :--- |
| R | `funct7` `rs2` `rs1` `funct3` `rd` `opcode` | None |
| I | `imm[11:0]` `rs1` `funct3` `rd` `opcode` | $\text{sext}(\text{inst}[31:20])$ |
| S | `imm[11:5]` `rs2` `rs1` `funct3` `imm[4:0]` `opcode` | $\text{sext}(\text{inst}[31:25] \,\Vert\, \text{inst}[11:7])$ |
| B | `imm[12\|10:5]` `rs2` `rs1` `funct3` `imm[4:1\|11]` `opcode` | 13-bit offset, multiple of 2 |
| U | `imm[31:12]` `rd` `opcode` | $\text{inst}[31:12] \ll 12$ |
| J | `imm[20\|10:1\|11\|19:12]` `rd` `opcode` | 21-bit offset, multiple of 2 |

The manual rearranges the bits of the B and J immediates so that most of them coincide with the S and I formats, which reduces hardware multiplexing. The B and J offsets are always multiples of 2 because immediate bit 0 is zero.

## 3. The 37 Base Instructions

The manual counts 40 instructions in the RV32I base (section 1.1). The 37 below operate on registers and memory; `FENCE`, `ECALL`, and `EBREAK` complete the 40 and appear in section 5. No integer computational instruction raises an arithmetic exception (section 1.1.4).

Table conventions: `sext` sign-extends, `zext` zero-extends, `<s` and `<u` compare signed and unsigned, `>>u` and `>>s` shift logically and arithmetically, and `ea` is the effective address $x[rs1] + \text{sext}(\text{off})$. The `shamt` is `inst[24:20]`.

| Instruction | Format | `opcode` | `funct3` | `funct7` | Semantics | Manual section |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `LUI` | U | `0110111` | - | - | `x[rd] = imm << 12` | 1.1.4.1 |
| `AUIPC` | U | `0010111` | - | - | `x[rd] = pc + (imm << 12)` | 1.1.4.1 |
| `JAL` | J | `1101111` | - | - | `x[rd] = pc + 4; pc = pc + sext(off)` | 1.1.5.1 |
| `JALR` | I | `1100111` | `000` | - | `t = pc + 4; pc = (x[rs1] + sext(off)) & ~1; x[rd] = t` | 1.1.5.1 |
| `BEQ` | B | `1100011` | `000` | - | `if (x[rs1] == x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BNE` | B | `1100011` | `001` | - | `if (x[rs1] != x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BLT` | B | `1100011` | `100` | - | `if (x[rs1] <s x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BGE` | B | `1100011` | `101` | - | `if (x[rs1] >=s x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BLTU` | B | `1100011` | `110` | - | `if (x[rs1] <u x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BGEU` | B | `1100011` | `111` | - | `if (x[rs1] >=u x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `LB` | I | `0000011` | `000` | - | `x[rd] = sext(M[ea][7:0])` | 1.1.6 |
| `LH` | I | `0000011` | `001` | - | `x[rd] = sext(M[ea][15:0])` | 1.1.6 |
| `LW` | I | `0000011` | `010` | - | `x[rd] = M[ea][31:0]` | 1.1.6 |
| `LBU` | I | `0000011` | `100` | - | `x[rd] = zext(M[ea][7:0])` | 1.1.6 |
| `LHU` | I | `0000011` | `101` | - | `x[rd] = zext(M[ea][15:0])` | 1.1.6 |
| `SB` | S | `0100011` | `000` | - | `M[ea] = x[rs2][7:0]` | 1.1.6 |
| `SH` | S | `0100011` | `001` | - | `M[ea] = x[rs2][15:0]` | 1.1.6 |
| `SW` | S | `0100011` | `010` | - | `M[ea] = x[rs2][31:0]` | 1.1.6 |
| `ADDI` | I | `0010011` | `000` | - | `x[rd] = x[rs1] + sext(imm)` | 1.1.4.1 |
| `SLTI` | I | `0010011` | `010` | - | `x[rd] = (x[rs1] <s sext(imm)) ? 1 : 0` | 1.1.4.1 |
| `SLTIU` | I | `0010011` | `011` | - | `x[rd] = (x[rs1] <u sext(imm)) ? 1 : 0` | 1.1.4.1 |
| `XORI` | I | `0010011` | `100` | - | `x[rd] = x[rs1] ^ sext(imm)` | 1.1.4.1 |
| `ORI` | I | `0010011` | `110` | - | `x[rd] = x[rs1] \| sext(imm)` | 1.1.4.1 |
| `ANDI` | I | `0010011` | `111` | - | `x[rd] = x[rs1] & sext(imm)` | 1.1.4.1 |
| `SLLI` | I | `0010011` | `001` | `0000000` | `x[rd] = x[rs1] << shamt` | 1.1.4.1 |
| `SRLI` | I | `0010011` | `101` | `0000000` | `x[rd] = x[rs1] >>u shamt` | 1.1.4.1 |
| `SRAI` | I | `0010011` | `101` | `0100000` | `x[rd] = x[rs1] >>s shamt` | 1.1.4.1 |
| `ADD` | R | `0110011` | `000` | `0000000` | `x[rd] = x[rs1] + x[rs2]` | 1.1.4.2 |
| `SUB` | R | `0110011` | `000` | `0100000` | `x[rd] = x[rs1] - x[rs2]` | 1.1.4.2 |
| `SLL` | R | `0110011` | `001` | `0000000` | `x[rd] = x[rs1] << x[rs2][4:0]` | 1.1.4.2 |
| `SLT` | R | `0110011` | `010` | `0000000` | `x[rd] = (x[rs1] <s x[rs2]) ? 1 : 0` | 1.1.4.2 |
| `SLTU` | R | `0110011` | `011` | `0000000` | `x[rd] = (x[rs1] <u x[rs2]) ? 1 : 0` | 1.1.4.2 |
| `XOR` | R | `0110011` | `100` | `0000000` | `x[rd] = x[rs1] ^ x[rs2]` | 1.1.4.2 |
| `SRL` | R | `0110011` | `101` | `0000000` | `x[rd] = x[rs1] >>u x[rs2][4:0]` | 1.1.4.2 |
| `SRA` | R | `0110011` | `101` | `0100000` | `x[rd] = x[rs1] >>s x[rs2][4:0]` | 1.1.4.2 |
| `OR` | R | `0110011` | `110` | `0000000` | `x[rd] = x[rs1] \| x[rs2]` | 1.1.4.2 |
| `AND` | R | `0110011` | `111` | `0000000` | `x[rd] = x[rs1] & x[rs2]` | 1.1.4.2 |

### 3.1. Rules per Group

| Group | Manual rule | Section |
| :--- | :--- | :--- |
| Arithmetic | `ADD`, `SUB`, and `ADDI` ignore overflow and write the low 32 bits | 1.1.4 |
| Comparison | `SLTIU` sign-extends the immediate and only then treats it as unsigned | 1.1.4.1 |
| Constant shifts | Bit 30 selects between logical and arithmetic right shift | 1.1.4.1 |
| Register shifts | The shift amount is the low 5 bits of `rs2` | 1.1.4.2 |
| `AUIPC` | Adds the upper immediate to the address of the instruction itself | 1.1.4.1 |
| Jumps and branches | There is no delay slot | 1.1.5 |
| `JAL` | Reach of $\pm 1$ MiB from the `pc` | 1.1.5.1 |
| `JALR` | Adds `rs1` to the unscaled 12-bit offset and clears bit 0 of the result | 1.1.5.1 |
| Conditional branches | Reach of $\pm 4$ KiB from the `pc` | 1.1.5.2 |
| Loads | Deliver the byte, halfword, or word to the register, with sign extension (`LB`, `LH`) or zero extension (`LBU`, `LHU`) | 1.1.6 |
| Stores | Write the low 8, 16, or 32 bits of `rs2` | 1.1.6 |

In the Core, the ALU, the decoder, and the extenders implement each row of the instruction table; the control-signal table for each instruction is in [DECODER.md](DECODER.md) and the ALU operation is in [ULA.md](ULA.md).

## 4. Data Memory

Manual section 1.1.6.

| Requirement | Rule |
| :--- | :--- |
| Address space | Byte-addressed, 32 bits |
| Byte order | Defined by the execution environment; in little-endian the least significant byte sits at the lowest address |
| Naturally aligned access | Never raises a misalignment exception |
| Misaligned access | The execution environment defines whether it completes, raises a misalignment or access exception, and whether the exception is fatal; the access may be slow and is not guaranteed atomic |
| Load with destination `x0` | Still raises exceptions and causes side effects |

The Core uses little-endian order. In the 32-bit word, the byte at address $4k + i$ occupies bits $[8i + 7 : 8i]$, and the store manager and the load extender use the two low bits of the effective address to select the byte lane. A load with destination `x0` accesses memory and goes through the same alignment check; it only skips writing the result.

Misaligned accesses within main memory run in hardware when the `has_zicclsm` generic is enabled (default); all others raise the misaligned load or store exception (causes 4 and 6). The cases are in [Zicclsm/description.md](../Zicclsm/description.md).

## 5. `FENCE`, `ECALL`, and `EBREAK`

### 5.1. `FENCE`

Manual section 1.1.7. The instruction orders device I/O and memory operations, as seen by other harts and devices, according to the predecessor and successor sets (any combination of I, O, R, and W) and the `fm` field. The `rs1` and `rd` fields are reserved; base implementations ignore them. Reserved values of `fm`, predecessor, and successor are treated as a normal `FENCE`, and `FENCE.TSO` may be implemented as `FENCE RW,RW`. The manual allows a minimal implementation to execute `FENCE` as a `NOP`.

| Aspect | Core behavior |
| :--- | :--- |
| Decoding | Legal when `opcode` is `0001111` and `funct3` is `000`, without examining `fm`, predecessor, successor, `rs1`, or `rd` |
| Effect | None; the decoder delivers the signals of a `NOP` (no register write and no memory access) |
| `FENCE.TSO` and reserved values | Execute as the plain `FENCE`, because the decoder examines only `opcode` and `funct3` |
| `FENCE.I` | Belongs to the Zifencei extension and is illegal when the `has_zifencei` generic is disabled ([Zifencei/description.md](../Zifencei/description.md)) |

### 5.2. `ECALL` and `EBREAK`

Manual section 1.1.8. Both are I-format SYSTEM instructions. `ECALL` requests a service from the execution environment, with parameters defined by it, and `EBREAK` returns control to a debugger. The manual allows simple implementations to handle all SYSTEM instructions with a single trap.

| Condition | `ECALL` | `EBREAK` |
| :--- | :--- | :--- |
| Encoding required by the Core | `opcode` `1110011`, `funct3` `000`, `rd` and `rs1` equal to `x0`, `funct12` field (bits 31 to 20) equal to `0x000` | Same, with `funct12` equal to `0x001` |
| With the Zicsr extension | Exception with cause 11 (machine-mode environment call), `mtval` equal to 0, and `pc` redirected to `mtvec` | Exception with cause 3 (breakpoint), `mtval` equal to 0, and `pc` redirected to `mtvec` |
| Without the Zicsr extension | The Core `o_trap` output flags the event, with the cause and the instruction `pc`; execution continues without redirection | Same as `ECALL`, with cause 3 |

Any other SYSTEM instruction that is not a CSR access, `MRET`, or `WFI`, including `ECALL` or `EBREAK` with `rd` or `rs1` different from `x0`, is illegal and raises cause 2. The trap details are in [ARCHITECTURE.md](../../pipeline/ARCHITECTURE.md), section 3.2.

## 6. `NOP` and HINT Instructions

Manual sections 1.1.4.3 and 1.1.9. The canonical `NOP` is `ADDI x0, x0, 0`. HINT instructions, mostly computational with `rd` equal to `x0` or a `FENCE` with an empty set, change only the `pc` and performance counters, and a simple implementation may execute them as ordinary instructions with no visible effect.

The Core executes computational HINTs as ordinary instructions, and discarding the write to `x0` makes them effect-free. The semihosting markers (`SLLI x0, x0, 31` and `SRAI x0, x0, 7`) follow the same path. `PAUSE` is a `FENCE` and executes as a `NOP`.

## 7. Jump Target Alignment

Manual sections 1.1.2, 1.1.5.1, and 1.1.5.2. With `IALIGN` equal to 32, a taken jump or branch whose target is not a multiple of 4 raises the instruction-address-misaligned exception, reported on the jump instruction and not on the target. A not-taken conditional branch never raises it.

| Aspect | Core behavior |
| :--- | :--- |
| `IALIGN` | 32; the Core does not implement compressed instructions |
| Check | In EX, on the target of taken `JAL`, `JALR`, and branches; it suffices that target bit 1 is 1 (bit 0 is already zero) |
| With the Zicsr extension | Exception with cause 0 and `mtval` equal to the target |
| Without the Zicsr extension | Target alignment is not checked |

## 8. Reserved and Illegal Instructions

Manual section 1.1.2: the behavior of reserved encodings is unspecified, and some platforms require an illegal-instruction exception. The Core classifies as illegal every word that is not a base instruction, `FENCE`, SYSTEM, or an instruction of an active extension, which includes the cases in the table.

| Illegal case | Example |
| :--- | :--- |
| Bits `[1:0]` different from `11` | Compressed instructions |
| Nonexistent `opcode` | `1111111` |
| `funct3` invalid for the `opcode` | `LOAD` with `funct3` `011`; `STORE` with `funct3` `011`; `BRANCH` with `funct3` `010`; `JALR` with `funct3` different from `000` |
| Invalid `funct7` in a constant shift | `SLLI` with `funct7` different from `0000000` |
| Invalid `funct7` in an R-format instruction | `SUB` and `SRA` are the only ones with `funct7` `0100000` |

With the Zicsr extension, an illegal instruction raises the cause 2 exception; without it, the `o_trap` output flags the event. Multiplication and division, CSR access, and `FENCE.I` stop being illegal when the corresponding extension is active.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
