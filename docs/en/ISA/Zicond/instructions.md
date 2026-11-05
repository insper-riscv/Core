# Zicond: Instructions

Chapter 10 of the manual ([Zicond Extension for Integer Conditional Operations, Version 1.0.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicond.html)).

This document gathers what the RISC-V manual requires of the `Zicond` extension. The source is the unprivileged ISA manual v20260120, chapter 10, section 10.1. The implementation in the Core is in [description.md](description.md).

## 1. Overview

Both instructions use the R-type format and the register-register `opcode`. Each reads `rs1` and `rs2`, writes the 32-bit result to `rd` and raises no exception. In RV32, `XLEN` is 32.

| Field | Bits | Value |
| :--- | :--- | :--- |
| `opcode` | [6:0] | `0110011` |
| `funct7` | [31:25] | `0000111` |
| `funct3` | [14:12] | `101` (`czero.eqz`) or `111` (`czero.nez`) |

## 2. Semantics (section 10.1.1)

| Instruction | Condition on `rs2` | `rd` |
| :--- | :--- | :--- |
| `czero.eqz rd, rs1, rs2` | $rs2 = 0$ | $0$ |
| `czero.eqz rd, rs1, rs2` | $rs2 \ne 0$ | $rs1$ |
| `czero.nez rd, rs1, rs2` | $rs2 \ne 0$ | $0$ |
| `czero.nez rd, rs1, rs2` | $rs2 = 0$ | $rs1$ |

The condition looks at the whole 32-bit value of `rs2`: a single bit set, in any position, makes it nonzero. When `rd` is `x0` the write is discarded, as in any instruction, and when `rs1` is `x0` the result is always zero.

## 3. Usage Sequences (section 10.1.2)

The manual builds conditional operations from the two instructions, with `rc` as the condition register.

| Operation | Sequence |
| :--- | :--- |
| Conditional add if zero | `czero.nez rd, rs2, rc` and `add rd, rs1, rd` |
| Conditional select if zero | `czero.nez rd, rs1, rc`, `czero.eqz rtmp, rs2, rc` and `add rd, rd, rtmp` |
| Conditional AND if zero | `and rd, rs1, rs2`, `czero.eqz rtmp, rs1, rc` and `or rd, rd, rtmp` |

The conditional subtract, OR and XOR follow the shape of the add, with the matching instruction in place of `add`. The "if nonzero" version swaps `czero.nez` for `czero.eqz`.

## 4. References

| Chapter | Section | Title |
| :--- | :--- | :--- |
| 10 | 10.1 | "Zicond" Extension for Integer Conditional Operations, Version 1.0.0 |
| 10 | 10.1.1 | Instructions (czero.eqz and czero.nez) |
| 10 | 10.1.2 | Usage examples |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
