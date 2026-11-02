# Zihpm, what the manual requires

Chapter 6 of the manual ([Zicntr and Zihpm Extensions for Counters](https://docs.riscv.org/reference/isa/v20260120/unpriv/counters.html)).

This document summarizes what the unprivileged ISA manual (version 20260120) requires of the Zihpm extension. The source is Chapter 6, "Zicntr and Zihpm Extensions for Counters, Version 2.0", section 6.1.2, and the text below is a paraphrase. The chapter also defines Zicntr, described in [Zicntr](../Zicntr/instructions.md). How the Core implements each point is in [description.md](description.md), and the CSR access instructions themselves (`CSRRW`, `CSRRS`, `CSRRC` and variants) are in [Zicsr](../Zicsr/instructions.md).

## 1. Overview (Chapter 6, Section 6.1.2)

The extension gives unprivileged code access to up to 29 performance counters of 64 bits. Each counter is read through a read-only CSR of `XLEN` bits, at addresses $0xC03$ to $0xC1F$. On RV32 (`XLEN = 32`) the upper halves sit at addresses $0xC83$ to $0xC9F$. The extension depends on Zicsr.

## 2. Zihpm, performance counters (Section 6.1.2)
Zihpm adds up to 29 counters of 64 bits, `hpmcounter3` to `hpmcounter31`, at addresses $0xC03$ to $0xC1F$. On RV32 the upper halves are `hpmcounter3h` to `hpmcounter31h`, at addresses $0xC83$ to $0xC9F$.

| Aspect | What the manual says |
| :--- | :--- |
| Quantity | Platform dependent, from zero to 29 |
| Width | 64 bits |
| Events counted | Defined by the platform |
| Unimplemented counter | Access may raise an illegal-instruction exception or return a constant |
| Access control | Described in the privileged architecture manual |

## 3. Out of scope for this chapter

The chapter does not define the machine CSRs that control the performance counters, such as `mhpmcounterN`, `mhpmeventN` and `mcountinhibit`. These registers, the event selector and the count inhibit belong to the privileged architecture manual, which was not consulted for this document. What the Core offers at these addresses is described in [description.md](description.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
