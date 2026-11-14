# Zicsr: Boot Fragment

The `src/Zicsr/boot.inc` fragment leaves the machine state with no interrupt enabled or pending and with a safe trap handler. The inclusion contract, the order and the registers used are in [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Macro | `RV32_HAS_ZICSR`, with `RV32_HAS_INTERRUPTS` for `mip` |
| Source | Volume II of the RISC-V manual (privileged ISA, version 20260120), sections 2.1.1.6, 2.1.1.7, 2.1.1.9 and 2.1.1.13 |
| Temporary register | `t0` |
| External symbol | `rv32_boot_trap`, defined by the includer, aligned to 4 bytes |

## 2. State left

| CSR | Value | Reason |
| :--- | :--- | :--- |
| `mstatus` | 0 | `MIE` at 0 turns the global interrupts off, and `MPIE` at 0 stops an `mret` from reopening them |
| `mie` | 0 | No interrupt source enabled, including the `LCOFIE` of Sscofpmf |
| `mscratch` | 0 | Known value for the first use by the application handler |
| `mtvec` | Address of `rv32_boot_trap`, direct `MODE` | The address is a multiple of 4, so bits 1 and 0 are 0 and every trap goes to the safe handler |
| `mip` | 0, only with `RV32_HAS_INTERRUPTS` | The program writes only the bits the hart lets it write, the others mirror the platform |

With `RV32_HAS_ACCESS_FAULTS` there is nothing more to initialize, because `mtvec` already covers the access fault trap.

## 3. Size

It is 6 instructions (24 bytes), and 7 (28 bytes) with `RV32_HAS_INTERRUPTS`. The handler address is formed relative to `pc`, which does not depend on the address where the BOOT is assembled.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
