# M Extension: Instructions

Chapter 11 of the manual ([M Extension for Integer Multiplication and Division](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)).

This document gathers what the RISC-V manual requires of the `M` extension (integer multiplication and division). The source is the unprivileged ISA manual v20260120, chapter 11 ("M" Extension for Integer Multiplication and Division, Version 2.0). `M` implies `Zmmul`, which holds the four multiplication instructions and is described in [Zmmul](../Zmmul/instructions.md). The implementation in the Core is in [description.md](description.md).

## 1. Overview

All instructions use the R-type format and share the register-register `opcode` and the `funct7` value that identifies the extension; only `funct3` tells the operations apart.

| Field | Bits | Value |
| :--- | :--- | :--- |
| `opcode` | [6:0] | `0110011` |
| `funct7` | [31:25] | `0000001` |
| `funct3` | [14:12] | Selects the operation (section 2) |

The operands are `rs1` and `rs2`, and the 32-bit result goes to `rd`. On RV32, `XLEN` is 32.

## 2. Encoding

| Instruction | `funct3` | Group | Manual section |
| :--- | :--- | :--- | :--- |
| `MUL` | `000` | Multiplication | 11.1.1 |
| `MULH` | `001` | Multiplication | 11.1.1 |
| `MULHSU` | `010` | Multiplication | 11.1.1 |
| `MULHU` | `011` | Multiplication | 11.1.1 |
| `DIV` | `100` | Division | 11.1.2 |
| `DIVU` | `101` | Division | 11.1.2 |
| `REM` | `110` | Division | 11.1.2 |
| `REMU` | `111` | Division | 11.1.2 |

Bit 2 of `funct3` separates the two groups, and in the divisions bit 0 separates the signed version from the unsigned one.

## 3. Multiplication (section 11.1.1)

The four multiplication instructions (`MUL`, `MULH`, `MULHSU` and `MULHU`) are those of `Zmmul`. Their semantics and the sequence that obtains the full product are in [Zmmul](../Zmmul/instructions.md).

## 4. Division (section 11.1.2)

| Instruction | Operands | Result |
| :--- | :--- | :--- |
| `DIV` | Signed | Quotient of `rs1` by `rs2`, rounded toward zero |
| `DIVU` | Unsigned | Quotient of `rs1` by `rs2`, rounded toward zero |
| `REM` | Signed | Division remainder, with the sign of the dividend when nonzero |
| `REMU` | Unsigned | Division remainder |

Except for overflow, the identity below holds for dividend $n$, divisor $d$, quotient $q$ and remainder $r$.

$$
n = d \cdot q + r
$$

### 4.1. Special Cases

The manual (table 1 of section 11.1.2) defines the result without raising an exception.

| Condition | Quotient (`DIV`, `DIVU`) | Remainder (`REM`, `REMU`) |
| :--- | :--- | :--- |
| Division by zero | All bits set (`0xFFFFFFFF`) | Equal to the dividend |
| Signed overflow ($-2^{31} \div -1$) | Equal to the dividend ($-2^{31}$) | $0$ |

Unsigned division cannot overflow. The manual justifies the all-ones quotient as the largest unsigned value, which simple unsigned dividers produce naturally, and rejects an exception on division by zero because it would make division the only arithmetic operation in the ISA to trap.

### 4.2. Obtaining Quotient and Remainder

To obtain both, the manual says to issue `DIV[U] rdq, rs1, rs2` followed by `REM[U] rdr, rs1, rs2`, with `rdq` different from `rs1` and `rs2`. The microarchitecture may fuse the sequence into a single division.

## 5. References

| Chapter | Section | Title |
| :--- | :--- | :--- |
| 11 | 11.1 | "M" Extension for Integer Multiplication and Division, Version 2.0 |
| 11 | 11.1.1 | Multiplication Operations |
| 11 | 11.1.2 | Division Operations |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
