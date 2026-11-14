# Zicntr: Boot Fragment

The `src/Zicntr/boot.inc` fragment clears the machine counters and leaves them counting. The inclusion contract, the order and the registers used are in [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Macro | `RV32_HAS_ZICNTR` |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), chapter 6, section 6.1, and volume II, sections 2.1.1.10 and 2.1.1.12 |
| Temporary register | None |

## 2. State left

| CSR | Value | Reason |
| :--- | :--- | :--- |
| `mcycle` and `mcycleh` | 0 | The cycle count of the application starts at the end of the BOOT |
| `minstret` and `minstreth` | 0 | The instruction count starts at the end of the BOOT |
| `mcountinhibit`, bits 0 and 2 | 0 | Both counters run. Bits 3 to 31 belong to Zihpm |

Both counters are inhibited while the halves are written, so the low half does not advance between one write and the other, and released at the end.

`mcounteren` is not written, because the Core has only M mode and the register does not exist. `time` is read-only and belongs to the platform.

## 3. Size

It is 6 instructions (24 bytes), with no temporary register.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
