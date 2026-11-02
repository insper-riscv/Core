# Zicntr and Zihpm, what the manual requires

This document summarizes what the unprivileged ISA manual (version 20260120) requires of the counter extensions. The source is Chapter 6, "Zicntr and Zihpm Extensions for Counters, Version 2.0", and the text below is a paraphrase. How the Core implements each point is in [description.md](description.md), and the CSR access instructions themselves (`CSRRW`, `CSRRS`, `CSRRC` and variants) are in [Zicsr](../Zicsr/instructions.md).

## 1. Overview (Chapter 6, Section 6.1)

The two extensions give unprivileged code access to up to 32 counters and timers of 64 bits. Each counter is read through a read-only CSR of `XLEN` bits, and these CSRs occupy the range $0xC00$ to $0xC1F$. On RV32 (`XLEN = 32`) the upper halves sit in the range $0xC80$ to $0xC9F$.

| Extension | Counters | Manual section | Depends on |
| :--- | :--- | :--- | :--- |
| Zicntr | `cycle`, `time`, `instret` | 6.1.1 | Zicsr |
| Zihpm | `hpmcounter3` to `hpmcounter31` | 6.1.2 | Zicsr |

## 2. Zicntr, base counters (Section 6.1.1)

### 2.1. The three counters

| CSR (low half) | CSR (high half, RV32) | What it measures |
| :--- | :--- | :--- |
| `cycle` | `cycleh` | Execution cycles of the core |
| `time` | `timeh` | Wall-clock time |
| `instret` | `instreth` | Instructions retired by the hart |

The individual addresses are $0xC00$, $0xC01$ and $0xC02$ for the low halves and $0xC80$, $0xC81$ and $0xC82$ for the high ones.

Manual rules for each counter:

1. `cycle` counts cycles of the core. Its behavior during a sleep state depends on the execution environment.
2. `time` counts wall-clock time. The harts of a system must be synchronized to within one tick, and software must observe `time` as monotonically nondecreasing. The tick period is defined by the execution environment.
3. `instret` counts the instructions retired by the hart. An instruction that causes a synchronous exception, including `ECALL` and `EBREAK`, does not increment the counter.

### 2.2. Width and reading on RV32

The counters are 64 bits wide even when `XLEN = 32`, so software can detect overflow. On RV32 a 64-bit read takes two CSR instructions, one per half. To get a coherent value even if the low half overflows between the two reads, the manual shows a sequence of three reads.

1. Read the high half (`cycleh`).
2. Read the low half (`cycle`).
3. Read the high half again and repeat everything if the two high-half reads differ.

### 2.3. Access

The counter CSRs are read-only at the unprivileged level, and an effective write to them is an attempt to write a read-only CSR (Zicsr rule). The manual lets an execution environment prohibit access to the counters, for example to hinder timing side-channel attacks.

## 3. Zihpm, performance counters (Section 6.1.2)

Zihpm adds up to 29 counters of 64 bits, `hpmcounter3` to `hpmcounter31`, at addresses $0xC03$ to $0xC1F$. On RV32 the upper halves are `hpmcounter3h` to `hpmcounter31h`, at addresses $0xC83$ to $0xC9F$.

| Aspect | What the manual says |
| :--- | :--- |
| Quantity | Platform dependent, from zero to 29 |
| Width | 64 bits |
| Events counted | Defined by the platform |
| Unimplemented counter | Access may raise an illegal-instruction exception or return a constant |
| Access control | Described in the privileged architecture manual |

## 4. Out of scope for this chapter

The chapter does not define the machine-level CSRs that control the counters, such as `mcycle`, `minstret`, `mhpmcounterN`, `mhpmeventN` and `mcountinhibit`. These registers, the event selector and the counting inhibit belong to the privileged architecture manual, which was not consulted for this document. What the Core offers at those addresses is described in [description.md](description.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
