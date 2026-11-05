# Zihpm, what the manual requires

Chapter 6 of the unprivileged manual ([Zicntr and Zihpm Extensions for Counters](https://docs.riscv.org/reference/isa/v20260120/unpriv/counters.html)) and chapter 1 of the privileged manual ([Control and Status Registers](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html)).

This document summarizes what the ISA manuals (version 20260120) require of the Zihpm extension. The sources are Chapter 6 of the unprivileged volume, "Zicntr and Zihpm Extensions for Counters, Version 2.0", section 6.1.2, and Chapter 1 of the privileged volume, with the machine CSR sections cited below. The text is a paraphrase. Chapter 6 also defines Zicntr, described in [Zicntr](../Zicntr/instructions.md). How the Core implements each point is in [description.md](description.md), and the access to the CSRs themselves (`CSRRW`, `CSRRS`, `CSRRC` and variants) is in [Zicsr](../Zicsr/instructions.md).

## 1. Overview (Chapter 6, Section 6.1.2)

The extension gives unprivileged code access to up to 29 performance counters of 64 bits. Each counter is read through a read-only CSR of `XLEN` bits, at addresses $0xC03$ to $0xC1F$. On RV32 (`XLEN = 32`) the upper halves sit at addresses $0xC83$ to $0xC9F$. The extension depends on Zicsr.

## 2. Zihpm, performance counters (Section 6.1.2)

Zihpm adds up to 29 counters of 64 bits, `hpmcounter3` to `hpmcounter31`, at addresses $0xC03$ to $0xC1F$. On RV32 the upper halves are `hpmcounter3h` to `hpmcounter31h`, at addresses $0xC83$ to $0xC9F$.

| Aspect | What the manual says |
| :--- | :--- |
| Count | Depends on the platform, from zero to 29 |
| Width | 64 bits |
| Events counted | Defined by the platform |
| Unimplemented counter | The access may raise an illegal-instruction exception or return a constant |
| Access control | Described in the privileged architecture manual |
| 64-bit read on RV32 | The sequence high half, low half, high half recovers a valid value when the two reads of the high half match |

## 3. Machine counters (Chapter 1, privileged volume)

The machine CSRs that control the performance counters are in [section 2.1.1.10](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-10-hardware-performance-monitor) of the privileged manual, and the counting inhibit in [section 2.1.1.12](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-12-machine-counter-inhibit-mcountinhibit-register).

| Register | Address | What the manual says |
| :--- | :--- | :--- |
| `mhpmcounter3` to `mhpmcounter31` | $0xB03$ to $0xB1F$ | 64-bit counters, WARL registers; the read mirrors are the `hpmcounterN` |
| `mhpmcounter3h` to `mhpmcounter31h` | $0xB83$ to $0xB9F$ | Upper halves of the counters on RV32 |
| `mhpmevent3` to `mhpmevent31` | $0x323$ to $0x33F$ | WARL event selectors; the meaning of the events belongs to the platform and event 0 means no event |
| `mcountinhibit` | $0x320$ | 32-bit WARL register; bit 0 inhibits `mcycle`, bit 1 is always zero because `time` cannot be inhibited, bit 2 inhibits `minstret` and bits 3 to 31 inhibit each event counter |

The manual says that all counters should exist, but that fixing a counter and its event selector at zero is a legal implementation. A counter whose inhibit bit is one keeps its value, and a counter whose bit is zero counts normally. An explicit write to a counter in the same cycle as an event wins over the increment.

## 4. Addresses

The addresses of `hpmcounterN` are in the [table of unprivileged addresses](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-1-currently-allocated-risc-v-unprivileged-csr-addresses), and those of `mhpmcounterN`, `mhpmeventN` and `mcountinhibit` in the [table of machine addresses](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-4-currently-allocated-risc-v-machine-level-csr-addresses). What the Core offers at these addresses is described in [description.md](description.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
