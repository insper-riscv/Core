# RV32E: Reduced Base Integer Instruction Set

Chapter 2 of the manual ([RV32E and RV64E Base Integer Instruction Sets](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32e.html)).

This document summarizes what the RISC-V manual requires of the RV32E base. The source is the unprivileged ISA manual (v20260120), Chapter 2, "RV32E and RV64E Base Integer Instruction Sets, Version 2.0", section 2.1 and its subsections. The chapter only describes the differences from the RV32I base and is meant to be read after Chapter 1 ("RV32I Base Integer Instruction Set, Version 2.1"). The implementation in the Core is in [description.md](description.md).

## 1. Purpose (section 2.1)

The manual defines the RV32E as a reduced version of the RV32I aimed at embedded microcontrollers, whose only change is to reduce the number of integer registers to 16. Standard extensions compatible with the RV32I are also compatible with the RV32E unless stated otherwise.

## 2. Programmers' Model (section 2.1.1)

| Item | RV32I | RV32E |
| :--- | :--- | :--- |
| General-purpose integer registers | `x0` to `x31` | `x0` to `x15` |
| `x0` | Hardwired to zero | Hardwired to zero |

The manual justifies the reduction by area, since in small RV32I implementations the upper 16 registers take about a quarter of the core area excluding memories. Removing them saves about 25% of that area, with a matching power reduction.

## 3. Encoding (section 2.1.2)

RV32E instructions have the same encodings as the RV32I, except that only `x0` to `x15` exist. The manual declares every encoding that specifies `x16` to `x31` as reserved.

| Aspect | Manual requirement |
| :--- | :--- |
| Formats and opcodes | Identical to the RV32I |
| `rd`, `rs1` and `rs2` fields | May only name `x0` to `x15` |
| Encodings with `x16` to `x31` | Reserved, for future custom space or new standard encodings |

The manual does not define the hardware behavior for a reserved encoding in this section, and treating it as an illegal instruction is an implementation choice (see [description.md](description.md)).

## 4. Limits of the Chapter

Chapter 2 does not cover the calling convention (ABI), HINT instructions or CSRs. The RV32E ABI (`ilp32e`) comes from the RISC-V psABI specification, outside the unprivileged ISA manual, and this document does not describe its details.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
