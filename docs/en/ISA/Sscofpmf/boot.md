# Sscofpmf: Boot Fragment

The `src/Sscofpmf/boot.inc` fragment clears the overflow state of the event counters. The inclusion contract, the order and the registers used are in [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Macro | `RV32_HAS_SSCOFPMF`, which the Core accepts only with `HAS_ZIHPM` and `HAS_INTERRUPTS` |
| Source | Volume II of the RISC-V manual (privileged ISA, version 20260120), chapter 14 and sections 3.1.9 and 3.1.10 |
| Temporary register | `t0` |

## 2. State left

| CSR | Value | Reason |
| :--- | :--- | :--- |
| `mhpmevent3h` to `mhpmevent31h` | 0 | Clears `OF` (bit 31), which only a program write clears, and `MINH` (bit 30), so counting in machine mode stays on |
| `mip`, bit 13 (`LCOFIP`) | 0 | A counter may have overflowed before the Zihpm fragment cleared the selectors, and the pending bit stays after `OF` is cleared |

`LCOFIE`, bit 13 of `mie`, was already cleared by the Zicsr fragment. The Sscofpmf fragment comes after the Zihpm one, because the selectors must be at 0 before `OF` is cleared, and no counter counts again.

## 3. Size

It is 31 instructions (124 bytes), 29 CSR writes, the bit 13 mask and the clear in `mip`.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
