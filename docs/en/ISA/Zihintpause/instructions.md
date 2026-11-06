# Zihintpause: Instructions

Chapter 8 of the manual ([Zihintpause Extension for Pause Hint, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zihintpause.html)).

This document gathers what the RISC-V manual requires of the `Zihintpause` extension. The implementation in the Core is in [description.md](description.md).

## 1. Overview

`Zihintpause` defines the `pause` hint, which suggests that the implementation reduce the instruction rate of the hart for a short period, as in busy-wait loops. Being a hint (HINT), it may be executed as a `nop`, with no architectural effect and no exception.

## 2. Encoding

`pause` is a `FENCE` with `fm = 0000`, `pred = 0001` (write), `succ = 0000`, `rs1 = x0` and `rd = x0`.

| Instruction | Bits [31:20] | Bits [19:15] | Bits [14:12] | Bits [11:7] | Bits [6:0] | Word |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `pause` | `0000 0001 0000` | `00000` | `000` | `00000` | `0001111` | `0x0100000F` |

## 3. Semantics

| Aspect | Behavior |
| :--- | :--- |
| Registers | None changes |
| Memory | No access |
| Illegal-instruction exception | Never raised |

## 4. References

| Chapter | Title |
| :--- | :--- |
| 13 | "Zihintpause" Extension for Pause Hint, Version 2.0 |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
