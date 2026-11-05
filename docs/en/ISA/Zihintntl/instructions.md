# Zihintntl: Instructions

Chapter 12 of the manual ([Zihintntl Extension for Non-Temporal Locality Hints, Version 1.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zihintntl.html)).

This document gathers what the RISC-V manual requires of the `Zihintntl` extension. The implementation in the Core is in [description.md](description.md).

## 1. Overview

`Zihintntl` defines four non-temporal locality hints. Each one tells the implementation that the memory access of the next instruction has no temporal locality in one of the cache domains. Like every RISC-V hint (HINT), it may be ignored, and an implementation that ignores it executes it as a `nop`, with no architectural effect and no exception.

## 2. Encoding

The hints are `ADD` with `rd = x0` and `rs1 = x0`. The `rs2` register selects the domain.

| Instruction | Equivalent to | Word |
| :--- | :--- | :--- |
| `ntl.p1` | `add x0, x0, x2` | `0x00200033` |
| `ntl.pall` | `add x0, x0, x3` | `0x00300033` |
| `ntl.s1` | `add x0, x0, x4` | `0x00400033` |
| `ntl.all` | `add x0, x0, x5` | `0x00500033` |

The compressed forms (`c.ntl.*`) belong to the `C` extension, which the Core does not implement.

## 3. Semantics

| Aspect | Behavior |
| :--- | :--- |
| Registers | None changes, since the write to `x0` is discarded |
| Memory | No access |
| Illegal-instruction exception | Never raised |

## 4. References

| Chapter | Title |
| :--- | :--- |
| 12 | "Zihintntl" Extension for Non-Temporal Locality Hints, Version 1.0 |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
