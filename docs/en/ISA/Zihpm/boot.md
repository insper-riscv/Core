# Zihpm: Boot Fragment

The `src/Zihpm/boot.inc` fragment leaves the 29 event counters with no event selected and cleared. The inclusion contract, the order and the registers used are in [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Macro | `RV32_HAS_ZIHPM` |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), chapter 6, section 6.2, and volume II, sections 2.1.1.10 and 2.1.1.12 |
| Temporary register | `t0` |

## 2. State left

| CSR | Value | Reason |
| :--- | :--- | :--- |
| `mhpmevent3` to `mhpmevent31` | 0 | Event 0 does not count, and the application picks the event it wants to measure |
| `mhpmcounter3` to `mhpmcounter31` | 0 | The measurement starts at the end of the BOOT |
| `mhpmcounter3h` to `mhpmcounter31h` | 0 | High half of the same counters |
| `mcountinhibit`, bits 3 to 31 | 0 | No event counter inhibited. Bits 0 to 2 belong to Zicntr |

The selectors are written before the counters, so no counter counts during the cleanup and a counter that the previous program left near overflow does not overflow between two writes. Releasing the inhibition comes last.

## 3. Core with part of the counters

The Core implements the first `hpm_counters` counters and answers the 29 addresses of each range. A write to an index without a counter is ignored and the read is zero, with no exception, so the fragment writes the 29 indices for any `hpm_counters` and `hpm_width`. The Core choice for the unimplemented counter is in [conformance.md](conformance.md).

## 4. Size

It is 89 instructions (356 bytes), 87 CSR writes, the mask and the release of the inhibition. The fragment repeats the write with an assembler directive, because the CSR address is an immediate of the instruction and does not allow a run-time loop.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
