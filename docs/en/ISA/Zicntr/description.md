# Zicntr in the Core

This document describes how the Core implements the base counters `cycle`, `time` and `instret`, and the 64-bit counter block that Zihpm also uses. What the manual requires is in [instructions.md](instructions.md), the performance counters are in [Zihpm](../Zihpm/description.md), and the CSR file that hosts them (read, atomic write, illegality) is in [Zicsr](../Zicsr/description.md).

## 1. Generics

| Generic | Entity | Default | Effect |
| :--- | :--- | :--- | :--- |
| `has_zicntr` | `core` | `false` | Instantiates `mcycle`, `minstret` and `time` with their mirrors, and the `mcountinhibit` register; requires `has_zicsr` |
| `tick_cycles` | `core` | 50 | Clock cycles per `time` tick (50 gives 1 MHz at 50 MHz) |

Elaboration fails if `has_zicntr` is on without `has_zicsr`. Zicntr is independent of Zihpm.

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

There are 3 counters of 64 bits. The Core does not implement `mcounteren`, and access to that address is illegal. The Core has only M-mode, and the privileged manual says that in harts without U-mode the `mcounteren` register should not exist ([section 2.1.1.11](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#mcounteren)).

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

The `mcountinhibit` register sits at `0x320`. Its writable bits depend on what the profile includes, and the other bits read zero and ignore writes. The register exists when there is `has_zicntr` or at least one event counter, and the event counter bits are in [Zihpm](../Zihpm/description.md).

| Bit | Inhibits | Exists when |
| :--- | :--- | :--- |
| 0 | `mcycle` | `has_zicntr` |
| 1 | Nothing (`time` cannot be inhibited) | Never |
| 2 | `minstret` | `has_zicntr` |

An inhibited counter keeps its value and stays readable and writable. Inhibiting `minstret` also suspends the sum of the pending retirement that the read shows.

## 5. Nonexistent address

Without `has_zicntr` the addresses of `mcycle`, `minstret`, `time`, their mirrors and `mcountinhibit` (when there is no event counter) are nonexistent. Reading or writing them signals an illegal CSR access, which the Core handles as an illegal-instruction exception (`mcause = 2`). There is no constant return value. The same holds for an effective write to `cycle`, `instret` and `time`.

## 6. Formal verification

| Proof | File | What it guarantees |
| :--- | :--- | :--- |
| `counter64` | `formal/counter64_props.sv` | The pair of halves is always the ideal 64-bit value, a write wins over the increment, the carry is never lost and the value does not decrease without a write (induction, cover) |
| `csr_file` with Zicntr | `formal/csr_cntr_props.sv` | Values read from `mcycle`, `minstret` and mirrors, write per half, read-only mirrors and `time`, bits 0 and 2 of `mcountinhibit` and retirement cancellation (6-cycle BMC, cover) |

The proof procedure is in [FORMAL.md](../../FORMAL.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
