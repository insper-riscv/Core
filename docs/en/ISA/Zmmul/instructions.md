# Zmmul: Instructions

Chapter 11 of the manual, section 11.1.3 ([Zmmul Extension, Version 1.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html#11-1-3-zmmul-extension-version-1-0)).

This document gathers what the RISC-V manual requires of the `Zmmul` extension, which holds only the multiplication subset of `M`. The source is the unprivileged ISA manual v20260120, chapter 11, section 11.1.3. Division, which `Zmmul` does not include, is in [M](../M/instructions.md). The implementation in the Core is in [description.md](description.md).

## 1. Overview

The instructions use the R-type format and the register-register `opcode` `0110011` and the `funct7` `0000001`, the same as `M`. Bit 2 of `funct3` is zero in the four instructions.

## 2. Encoding

| Instruction | `funct3` | Group | Manual section |
| :--- | :--- | :--- | :--- |
| `MUL` | `000` | Multiplication | 11.1.1 |
| `MULH` | `001` | Multiplication | 11.1.1 |
| `MULHSU` | `010` | Multiplication | 11.1.1 |
| `MULHU` | `011` | Multiplication | 11.1.1 |

## 3. Multiplication (section 11.1.1)

The full product of two 32-bit operands has 64 bits. Each instruction returns one half of it.

| Instruction | Interpretation of `rs1` | Interpretation of `rs2` | Result |
| :--- | :--- | :--- | :--- |
| `MUL` | Two's complement | Two's complement | Product bits [31:0] |
| `MULH` | Signed | Signed | Product bits [63:32] |
| `MULHSU` | Signed | Unsigned | Product bits [63:32] |
| `MULHU` | Unsigned | Unsigned | Product bits [63:32] |

The low 32 bits are the same for any interpretation of the operands, so `MUL` has no sign variants. `MULHSU` serves multi-word signed multiplication.

### 3.1. Obtaining the Full Product

To obtain both halves, the manual says to issue `MULH[[S]U] rdh, rs1, rs2` followed by `MUL rdl, rs1, rs2`, with the source operands in the same order and `rdh` different from `rs1` and `rs2`. The microarchitecture may fuse the sequence into a single multiplication.

## 4. Relation to M (section 11.1.3)

`Zmmul` (version 1.0) contains only the multiplication subset of `M`.

| Instruction | In `Zmmul` | In `M` |
| :--- | :--- | :--- |
| `MUL`, `MULH`, `MULHSU`, `MULHU` | Yes | Yes |
| `DIV`, `DIVU`, `REM`, `REMU` | No | Yes |

The encodings are identical to those of `M`. `M` implies `Zmmul`, so every implementation of `M` also contains `Zmmul`. The manual aims it at low-cost designs that need to multiply without dividing, common in microcontrollers and FPGA soft cores, where the multiplier is usually a dedicated block and the divider is ordinary logic.

## 5. References

| Chapter | Section | Title |
| :--- | :--- | :--- |
| 11 | 11.1.1 | Multiplication Operations |
| 11 | 11.1.3 | Zmmul Extension, Version 1.0 |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
