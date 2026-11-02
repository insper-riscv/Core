# Zicntr and Zihpm in the Core

This document describes how the Core implements the counters. What the manual requires is in [instructions.md](instructions.md), and the CSR file that hosts them (read, atomic write, illegality) is in [Zicsr](../Zicsr/description.md).

## 1. Generics

| Generic | Entity | Default | Effect |
| :--- | :--- | :--- | :--- |
| `has_zicntr` | `core` | `false` | Instantiates `mcycle`, `minstret` and `time` with their mirrors, and the `mcountinhibit` register; requires `has_zicsr` |
| `tick_cycles` | `core` | 50 | Clock cycles per `time` tick (50 gives 1 MHz at 50 MHz) |
| `has_zihpm` | `core` | `false` | Instantiates the four event counters; requires `has_zicsr` |
| `hpm_counters` | `core` | 0 | Number of event counters, from 0 to 4; when greater than 0 it takes precedence over `has_zihpm` |

With `has_zihpm = true` and `hpm_counters = 0` the Core instantiates 4 counters. Elaboration fails if any of the counter generics is on without `has_zicsr`.

Each extension is independent of the other, so Zihpm works without Zicntr. `mcountinhibit` exists when there is `has_zicntr` or at least one event counter.

## 2. 64-bit counter block

Every counter is an instance of `counter64`, which keeps the value in two halves of 32 bits.

| Aspect | Behavior |
| :--- | :--- |
| Increment | The low half adds 1 in the cycles with increment enabled |
| Carry | When the low half was at $2^{32}-1$, the carry is registered and the high half adds 1 in the next cycle, with no 64-bit adder in the combinational path |
| Read | The high half read already includes the pending carry, so the pair read is always the ideal 64-bit value |
| Write to the low half | Replaces the value and cancels the increment and the carry of the same cycle |
| Write to the high half | Replaces the value and drops the pending carry |
| Reset | Clears both halves and the carry |

A write wins over the increment of its own cycle, in each half.

## 3. Zicntr counters

### 3.1. Addresses and rules

There are 3 counters of 64 bits. The Core does not implement `mcounteren`, and access to that address is illegal.

| Counter | Low half | High half | Read-only mirror (low and high) | Increments | Write |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `mcycle` | `0xB00` | `0xB80` | `cycle` at `0xC00` and `0xC80` | Every clock cycle, including stall cycles, unless inhibited | Yes, in each half |
| `minstret` | `0xB02` | `0xB82` | `instret` at `0xC02` and `0xC82` | On every retired instruction, one cycle after the retirement, unless inhibited or canceled | Yes, in each half |
| `time` | `0xC01` | `0xC81` | Only the read form exists | On every divider tick, never inhibited | No |

Addresses `0xB01` and `0xB81` do not exist, and `time` has no machine form. An effective write to `cycle`, `instret` or `time` is an illegal access (`mcause = 2`). Without `has_zicntr` the counter addresses are nonexistent and access is illegal.

### 3.2. Instruction retirement

The instruction in EX retires when it is valid, the pipeline advances and there is no exception. The retire pulse stays pending for one cycle, so that a load or store exception taken in MEM cancels it, and the failing access does not count in `minstret`.

| Situation | Effect on `minstret` |
| :--- | :--- |
| Pending retirement | A read of `minstret` and `instret` already adds the pending retirement, and the actual addition happens in the next cycle |
| MEM exception in the next cycle | The retirement is canceled and does not count |
| Write to `minstret` in the same cycle | The retirement of the writing instruction itself is dropped |
| Instruction that raises an exception in EX | Produces no retire pulse |

### 3.3. Tick divider and `time`

`time` adds 1 on every pulse of the tick divider. The divider counts from 0 to $tick\_cycles - 1$, emits the pulse in the cycle where the count reaches the end and returns to 0 in the next cycle. Reset clears the count.

$$f_{time} = \frac{f_{clock}}{tick\_cycles}$$

The Core has no external time input. `time` derives from the Core's own clock, and the resolution is set by `tick_cycles` (at least 1).

## 4. `mcountinhibit`

The `mcountinhibit` register sits at `0x320`. Its writable bits depend on what the profile includes, and the other bits read zero and ignore writes.

| Bit | Inhibits | Exists when |
| :--- | :--- | :--- |
| 0 | `mcycle` | `has_zicntr` |
| 1 | Nothing (`time` cannot be inhibited) | Never |
| 2 | `minstret` | `has_zicntr` |
| $3+k$ | The event counter of index $3+k$ | $k < N$, with $N$ counters |

An inhibited counter keeps its value and stays readable and writable. Inhibiting `minstret` also suspends the addition of the pending retirement that a read shows.

## 5. Zihpm event counters

### 5.1. Organization

With $N$ counters (from 1 to 4), the Core implements the counters of indices 3 to $2+N$. Each counter of index $K$ has four counter addresses and one event selector.

| CSR | Address | Write |
| :--- | :--- | :--- |
| `mhpmeventK` | $0x320 + K$ | Yes, holds a 4-bit code (the upper bits read zero) |
| `mhpmcounterK` | $0xB00 + K$ | Yes |
| `mhpmcounterKh` | $0xB80 + K$ | Yes |
| `hpmcounterK` | $0xC00 + K$ | No |
| `hpmcounterKh` | $0xC80 + K$ | No |

The indices from 3 to 31 that the Core does not implement give an illegal access, like any nonexistent address. Writing `hpmcounterK` or `hpmcounterKh` is an illegal access. Each counter uses the 64-bit block of Section 2, and the event code is cleared on reset.

### 5.2. Counting rule

A counter adds 1 in every cycle where the bit of the event vector chosen by the code is `'1'`, the code is not zero and the counter's inhibit bit is `'0'`. A code outside the event table does not count.

### 5.3. Event table

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

## 6. Nonexistent address

The CSR file treats as nonexistent every counter address whose extension or index the profile does not include. Reading or writing it signals an illegal CSR access, which the Core handles as an illegal-instruction exception (`mcause = 2`). There is no constant return value. The same applies to an effective write to any read mirror.

## 7. Formal verification

| Proof | File | What it guarantees |
| :--- | :--- | :--- |
| `counter64` | `formal/counter64_props.sv` | The pair of halves is always the ideal 64-bit value, a write wins over the increment, the carry is never lost and the value does not decrease without a write (induction, cover) |
| `csr_file` with Zicntr | `formal/csr_cntr_props.sv` | Values read from `mcycle`, `minstret` and mirrors, write per half, read-only mirrors and `time`, bits 0 and 2 of `mcountinhibit` and retirement cancellation (6-cycle BMC, cover) |
| `csr_file` with Zihpm | `formal/csr_hpm_props.sv` | Event selection, inhibit, write per half, read-only mirrors and illegal addresses of the absent counters, with 4 counters and with 2 counters alongside Zicntr (6-cycle BMC, cover) |

The proof procedure is in [FORMAL.md](../../FORMAL.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
