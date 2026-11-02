# Zihpm in the Core

This document describes how the Core implements the Zihpm event counters. What the manual requires is in [instructions.md](instructions.md), the 64-bit counter block and `time` are in [Zicntr](../Zicntr/description.md), and the CSR file that hosts them (read, atomic write, illegality) is in [Zicsr](../Zicsr/description.md).

## 1. Generics

| Generic | Entity | Default | Effect |
| :--- | :--- | :--- | :--- |
| `has_zihpm` | `core` | `false` | Instantiates the four event counters; requires `has_zicsr` |
| `hpm_counters` | `core` | 0 | Number of event counters, from 0 to 4; when greater than 0 it takes precedence over `has_zihpm` |

With `has_zihpm = true` and `hpm_counters = 0` the Core instantiates 4 counters. Elaboration fails if any of the counter generics is on without `has_zicsr`. Zihpm is independent of Zicntr and works without it.

## 2. Organization

With $N$ counters (from 1 to 4), the Core implements the counters of indices 3 to $2+N$. Each counter of index $K$ has four counter addresses and one event selector.

| CSR | Address | Write |
| :--- | :--- | :--- |
| `mhpmeventK` | $0x320 + K$ | Yes, holds a 4-bit code (the upper bits read zero) |
| `mhpmcounterK` | $0xB00 + K$ | Yes |
| `mhpmcounterKh` | $0xB80 + K$ | Yes |
| `hpmcounterK` | $0xC00 + K$ | No |
| `hpmcounterKh` | $0xC80 + K$ | No |

The indices from 3 to 31 that the Core does not implement give an illegal access, like any nonexistent address. Writing `hpmcounterK` or `hpmcounterKh` is an illegal access. Each counter uses the 64-bit block described in [Zicntr](../Zicntr/description.md), and the event code is cleared on reset.

## 3. Counting rule

A counter adds 1 in every cycle where the bit of the event vector chosen by the code is `'1'`, the code is not zero and the counter's inhibit bit is `'0'`. A code outside the event table does not count.

## 4. Event table

The event vector has 16 bits, one per code, and bit 0 is always zero.

| Code | Event | Counting condition | Source |
| :---: | :--- | :--- | :--- |
| 0 | None | Never counts | Not applicable |
| 1 | Multiply or divide stall | Cycle in which the M unit holds the pipeline | Core |
| 2 | Wait for external memory | Cycle in which an access to the external RAM waits for the ready signal | Core |
| 3 | Branch or jump taken | Conditional branch with a true condition, `JAL` or `JALR`, with the pipeline advancing | Core |
| 4 | Misaligned access | First cycle of a misaligned access executed in two steps | Core |
| 5 | Instruction cache miss | Pulse from the instruction cache, on bit 0 of the external event input | Outside the Core |
| 6 | Data cache miss | Pulse from the data cache, on bit 1 of the external event input | Outside the Core |
| 7 | FLASH wait | FLASH wait cycle, on bit 2 of the external event input | Outside the Core |
| 8 | Load-use stall | Cycle in which load-use detection holds the fetch with no other stall active | Core |
| 9 | Fused operation | Cycle in which the M unit completes an operation by reusing the result of the previous one | Core |
| 10 to 15 | Reserved | Never count | Not applicable |

Event 9 counts the fusion of multiply or divide pairs (for example `MULH` followed by `MUL` with the same operands), described in [M](../M/description.md). Events 5 to 7 only count if the SoC drives the Core's external event input, which is zero by default.

## 5. `mcountinhibit`

The `mcountinhibit` register sits at `0x320`, and the `mcycle` and `minstret` bits are in [Zicntr](../Zicntr/description.md). The event counter bits depend on how many the profile includes, and the other bits read zero and ignore writes.

| Bit | Inhibits | Exists when |
| :--- | :--- | :--- |
| $3+k$ | The event counter of index $3+k$ | $k < N$, with $N$ counters |

An inhibited counter keeps its value and stays readable and writable.

## 6. Nonexistent address

The CSR file treats as nonexistent every performance counter address whose index the profile does not include. Reading or writing it signals an illegal CSR access, which the Core handles as an illegal-instruction exception (`mcause = 2`). There is no constant return value. The same holds for an effective write to `hpmcounterK` and `hpmcounterKh`.

## 7. Formal verification

| Proof | File | What it guarantees |
| :--- | :--- | :--- |
| `csr_file` with Zihpm | `formal/csr_hpm_props.sv` | Event selection, inhibit, write per half, read-only mirrors and illegal addresses of the absent counters, with 4 counters and with 2 counters alongside Zicntr (6-cycle BMC, cover) |

The proof procedure is in [FORMAL.md](../../FORMAL.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
