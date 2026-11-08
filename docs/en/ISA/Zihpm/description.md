# Zihpm in the Core

This document describes how the Core implements the Zihpm event counters. What the manual requires is in [instructions.md](instructions.md), the conformance of each requirement is in [conformance.md](conformance.md), the counter block and `time` are in [Zicntr](../Zicntr/description.md), and the CSR file that hosts the counters (read, atomic write, illegality) is in [Zicsr](../Zicsr/description.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 6, Zicntr and Zihpm Extensions for Counters, version 2.0 (section 6.2, Zihpm) |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |

## 2. Generics

| Generic | Entity | Default | Effect |
| :--- | :--- | :--- | :--- |
| `has_zihpm` | `core` | `false` | Turns the extension on: the 29 addresses of each range exist; requires `has_zicsr` |
| `hpm_counters` | `core` | 29 | Number of real counters, from 0 to 29, at indices 3 to $2+$`hpm_counters` |
| `hpm_width` | `core` | 64 | Width in bits of each real counter, from 0 to 64 |

Elaboration fails if `has_zihpm` is on without `has_zicsr`. Zihpm is independent of Zicntr and works without it. The two parameters for count and width belong to the profile manifest, and the value of `hpm_counters` and `hpm_width` of each profile comes from there.

With `hpm_width` equal to 0 no index has a real counter, as if `hpm_counters` were 0.

## 3. Organization

With `has_zihpm`, the Core defines the 29 indices from 3 to 31 in five ranges of 32 addresses. Index $K$ is the base address of the range plus $K$.

| CSR | Range | Write |
| :--- | :--- | :--- |
| `mhpmeventK` | $0x320 + K$ | Yes, holds a 4-bit code (the upper bits read zero) |
| `mhpmcounterK` | $0xB00 + K$ | Yes |
| `mhpmcounterKh` | $0xB80 + K$ | Yes |
| `hpmcounterK` | $0xC00 + K$ | No |
| `hpmcounterKh` | $0xC80 + K$ | No |

The bank decodes the range from the 7 upper bits of the address and the index from the 5 low bits, so the decoding does not compare the whole address. Writing `hpmcounterK` or `hpmcounterKh` is an illegal access at any index, because they are read-only CSRs. The addresses that the privileged manual does not define inside the ranges (`0x321`, `0x322`, `0xB01` and `0xB81`) are illegal.

### 3.1. Real indices and indices fixed at zero

| Index $K$ | Read of any CSR of the index | Write |
| :--- | :--- | :--- |
| $3 \le K < 3 + $`hpm_counters` | The register value | Effective, except on the mirrors |
| $K \ge 3 + $`hpm_counters` | Zero | Ignored, without an exception |

The manual allows fixing any counter at zero, but the address exists, so an access to an index without a counter raises no exception. A program finds how many counters the profile has by writing a pattern to `mhpmcounterK` and reading it back.

### 3.2. Counter width

A counter of $W$ bits (`hpm_width`) keeps the $\min(W,32)$ low bits in the low half and the remaining $W-32$ bits in the high half, when $W>32$. The bits of each half above the width read zero, and a write keeps only the bits that fit. The counter returns to zero after $2^W-1$.

## 4. Structure

The `hpm_counter_bank` has, for each real counter, an event selector, an inhibit bit and a counter of its own. The counters share no adder, and each one is an instance of the block described in [Zicntr](../Zicntr/description.md), with the width of the high half set by `hpm_width`. The read picks the register by index with a multiplexer tree of 32 entries per range, and an index without a counter returns zero.

## 5. Counting rule

A counter adds 1 in every cycle where the bit of the event vector chosen by the code is `'1'`, the code is not zero and the counter's inhibit bit is `'0'`. A code outside the event table does not count, even if the bit of the vector is `'1'`. An explicit write to a half wins over the increment of the same cycle.

## 6. Event table

The event vector has 16 bits, one per code, and bit 0 is always zero.

| Code | Event | Counting condition | Source |
| :---: | :--- | :--- | :--- |
| 0 | None | Never counts | Not applicable |
| 1 | Multiply or divide stall | Cycle where the M unit holds the pipeline | Core |
| 2 | Wait for external memory | Cycle where an access to the external RAM waits for the ready signal | Core |
| 3 | Taken branch or jump | Conditional branch with a true condition, `JAL` or `JALR`, with the pipeline running | Core |
| 4 | Misaligned access | First cycle of a misaligned access executed in two steps | Core |
| 5 | Instruction cache miss | Pulse of the instruction cache, on bit 0 of the external event input | Outside the Core |
| 6 | Data cache miss | Pulse of the data cache, on bit 1 of the external event input | Outside the Core |
| 7 | FLASH wait | FLASH wait cycle, on bit 2 of the external event input | Outside the Core |
| 8 | Load-use stall | Cycle where load-use detection holds the fetch with no other stall active | Core |
| 9 | Fused operation | Cycle where the M unit completes an operation reusing the result of the previous one | Core |
| 10 to 15 | Reserved | Never count | Not applicable |

Event 9 counts the fusion of multiply or divide pairs (for example `MULH` followed by `MUL` with the same operands), described in [M](../M/description.md). Events 5 to 7 only count if the SoC drives the external event input of the Core, which is zero by default.

## 7. `mcountinhibit`

The `mcountinhibit` register sits at `0x320`, and the bits of `mcycle` and `minstret` are in [Zicntr](../Zicntr/description.md). The register exists with `has_zicntr` or `has_zihpm`.

| Bit | Inhibits | Exists when |
| :--- | :--- | :--- |
| $3+k$ | The event counter of index $3+k$ | $k <$ `hpm_counters` |
| Other bits from 3 to 31 | Nothing | Never, they read zero and ignore writes |

An inhibited counter keeps its value and stays readable and writable.

## 8. Verification

| Layer | What it guarantees |
| :--- | :--- |
| Entity test of the bank | Each real index counts the chosen event, an index without a counter reads zero and ignores writes, inhibit acts per bit, an explicit write wins over the increment, the high half advances on the carry, the width truncates the high bits and a code outside the table counts zero, with 0, 1, 4 and 29 counters and widths of 1, 20, 32, 33, 40 and 64 bits |
| Formal proof of `csr_file` with Zihpm | `formal/csr_hpm_props.sv`: the 29 indices of the five ranges, the illegality of the mirrors and of the undefined addresses, the zero read past `hpm_counters`, the model of each counter and the decoding without overlap, with 29, 4, 2, 5 and 3 counters and widths of 64, 40, 20 and 0 bits, plus one mutant per property |
| Formal proof of `counter64` (in the Common-Components) | Ideal value of the chosen width, from 1 to 64 bits, with truncated writes |

The proof procedure is in [FORMAL.md](../../formal/FORMAL.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
