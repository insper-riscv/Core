# Zimop: Instructions

Chapter 9 of the manual, section 9.1 ([Zimop Extension for May-Be-Operations, Version 1.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zimop.html)).

This document gathers what the RISC-V manual requires of the `Zimop` extension. The source is the unprivileged ISA manual v20260120, chapter 9, section 9.1. The implementation in the Core is in [description.md](description.md).

## 1. Overview

`Zimop` reserves 40 encodings of the `SYSTEM` class as May-Be-Operations (MOPs). A future extension may give each one a meaning. Until then, a MOP writes zero to `rd` instead of doing nothing, which simplifies decoding and lets software detect the extension: a program that executes the MOP and finds a nonzero value in `rd` knows that another extension redefined it.

A MOP never causes an illegal-instruction exception when `Zimop` is present. This lets one binary run with or without the extension that redefines the MOP, and it is the reason `Zimop` exists as a separate extension.

## 2. Encoding

Both families use the `opcode` `1110011` (`SYSTEM`) and the `funct3` `100`. The bits of `n` are spread across the word, as the table shows.

| Instruction | Values of `n` | Bits [31:25] | Bits [24:20] | Bits [19:15] | Bits [14:12] | Bits [11:7] | Bits [6:0] |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `mop.r.n rd, rs1` | 0 to 31 (32 instructions) | `1 n[4] 00 n[3:2] 0` | `111 n[1:0]` | `rs1` | `100` | `rd` | `1110011` |
| `mop.rr.n rd, rs1, rs2` | 0 to 7 (8 instructions) | `1 n[2] 00 n[1:0] 1` | `rs2` | `rs1` | `100` | `rd` | `1110011` |

The reference words are `0x81C04073` for `mop.r.0` and `0x82004073` for `mop.rr.0`, with `rd`, `rs1` and `rs2` equal to `x0`.

## 3. Semantics

$$
x[rd] \leftarrow 0
$$

| Aspect | Behavior |
| :--- | :--- |
| Value written | Zero, to `rd`, for the 40 encodings |
| Read of `rs1` and `rs2` | The value read does not affect the result |
| `rd = x0` | No write, as in any instruction |
| Illegal-instruction exception | Never raised while the extension is present |

## 4. References

| Chapter | Section | Title |
| :--- | :--- | :--- |
| 9 | 9.1 | "Zimop" Extension for May-Be-Operations, Version 1.0 |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
