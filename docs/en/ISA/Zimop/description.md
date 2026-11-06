# Zimop: Implementation in the Core

This document describes how the Core executes the 40 `Zimop` instructions. What the manual requires, with the encodings, is in [instructions.md](instructions.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 9, Zimop Extension for May-Be-Operations, version 1.0 |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |

## 2. Configuration

| Generic | Default | Effect |
| :--- | :--- | :--- |
| `has_zimop` | `false` | Instantiates the decoder in the ID stage and executes `mop.r.n` and `mop.rr.n` |

With `has_zimop = false` the decoder is absent from the elaboration and the 40 encodings follow the path of any unsupported `SYSTEM` instruction. With `has_zicsr = true` this raises an illegal-instruction exception (cause 2), and without `has_zicsr` the exception signal of the core goes high. The rest of the core does not change with the extension on or off.

## 3. Decoding in the ID Stage

The decoder claims a word when it satisfies one of the conditions in the table. The fields `rd`, `rs1` and `rs2` and the bits of `n` do not take part in the decision.

| Family | Condition on the word |
| :--- | :--- |
| `mop.r.n` | `opcode = 1110011`, `funct3 = 100`, bit 31 set, bits [29:28] zero, bit 25 zero and bits [24:22] set |
| `mop.rr.n` | `opcode = 1110011`, `funct3 = 100`, bit 31 set, bits [29:28] zero and bit 25 set |

A claimed word enables the write to `rd` and replaces two signals that go on to the later stages.

| Signal | Value for a MOP | Reason |
| :--- | :--- | :--- |
| ALU operation | The `BGEU` branch operation, which selects no data result | The ALU result is zero |
| `opcode` shown to the EX stage | That of an arithmetic instruction with an immediate | The exception unit and the CSR bank do not treat the word as `SYSTEM` |

The `BGEU` operation only decides a branch when the `opcode` is the conditional-branch one, and the `opcode` shown to EX is another, so a MOP never changes the control flow.

## 4. Datapath

The zero follows the same path as the result of an arithmetic instruction. It crosses the `EX/MEM` and `MEM/WB` barrier registers, is forwarded to the following instructions by the forwarding unit and is written to `rd` in the WB stage. A MOP followed by an instruction that reads `rd` gives that instruction zero without a stall. The write to `x0` is discarded by the register file, as for any instruction.

## 5. Interactions

| Item | Behavior |
| :--- | :--- |
| RV32E | Bit 4 of `rd` set makes the instruction illegal, as for any instruction that writes `rd` |
| Zicsr | No CSR is read or written, and no exception is raised |
| Load hazard | The MOP counts as a reader of `rs1`, so a `load` right before it to the same register causes a one-cycle stall |

## 6. Verification

| Level | Coverage |
| :--- | :--- |
| Entity `zimop_decode` | The 32 encodings of `mop.r.n` and the 8 of `mop.rr.n` with several `rd`, `rs1` and `rs2`, and the flip of each fixed bit, which is no longer claimed |
| Core | The 40 encodings with a dirty destination, `rd = rs1` and `rd = x0`, with no exception logged |
| Formal | The decoder claims exactly the 40 families, writes `rd` and delivers the operation with no data result, with seven mutants rejected |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
