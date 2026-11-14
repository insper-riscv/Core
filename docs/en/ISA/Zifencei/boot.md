# Zifencei: Boot Fragment

The `src/Zifencei/boot.inc` fragment executes `fence.i`, so the instruction fetch sees everything the initialization wrote. The inclusion contract, the order and the registers used are in [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Macro | `RV32_HAS_ZIFENCEI` |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), chapter 4 |
| Temporary register | None |

## 2. State left

No CSR changes. `fence.i` is the last initialization instruction of the BOOT, so the next fetch, the one of the jump to the application, already sees the memory as the initialization left it.

On a core without Zifencei, `fence.i` is an illegal instruction, so the fragment generates the instruction only with `RV32_HAS_ZIFENCEI`. When the core has no instruction cache and no external instruction window, `fence.i` has no effect and the platform can drop the extension. The behavior of the instruction in the pipeline is in [description.md](description.md).

## 3. Size

It is 1 instruction (4 bytes).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
