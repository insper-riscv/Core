# Zifencei: Instructions Required by the RISC-V Manual

Chapter 4 of the manual ([Zifencei Extension for Instruction-Fetch Fence](https://docs.riscv.org/reference/isa/v20260120/unpriv/zifencei.html)).

This document summarises what the unprivileged ISA manual (version 20260120) requires of the Zifencei extension, described in Chapter 4, "Zifencei Extension for Instruction-Fetch Fence, Version 2.0". The extension defines a single instruction, `FENCE.I`. The Core implementation is in [description.md](description.md).

## 1. Scope of the Extension

Chapter 4 has a single section, 4.1, which defines the instruction and the rules of use. The extension exists because synchronisation between stores and instruction fetch is not part of the `I` base.

## 2. The FENCE.I Instruction

### 2.1. Encoding

The instruction uses the `MISC-MEM` opcode, shared with `FENCE`, and is told apart from it by the `funct3` field.

| Field | Bits | Value |
| :--- | :--- | :--- |
| `opcode` | $[6:0]$ | `0001111` (`MISC-MEM`) |
| `funct3` | $[14:12]$ | `001` |
| `funct12` | $[31:20]$ | Reserved, zero |
| `rs1` | $[19:15]$ | Reserved, zero |
| `rd` | $[11:7]$ | Reserved, zero |

The manual presents `funct12`, `rs1` and `rd` as unused fields, reserved for finer-grain fences in future extensions. By the forward-compatibility rule, base implementations must ignore them and standard software must zero them. The manual defines no immediate field of its own for the instruction; the `funct12` field takes the positions that an I-type instruction would use for the immediate.

### 2.2. Semantics

| Property | What the manual requires |
| :--- | :--- |
| Visibility on the same hart | A store to instruction memory is not guaranteed to be seen by the same hart's instruction fetch until that hart executes `FENCE.I` |
| Effect of the instruction | After `FENCE.I`, a later instruction fetch on the hart sees the earlier stores that were already visible to that hart |
| Ordering | The hart's earlier explicit memory accesses are ordered before its later instruction fetches |
| Fetch and the instruction's own accesses | An instruction fetch is ordered before the explicit memory accesses that the instruction itself causes |

### 2.3. Relation to FENCE

The ordinary `FENCE` orders data memory accesses, and `FENCE.I` orders those accesses against the hart's own instruction fetches. They are distinct instructions with different `funct3` values, and neither replaces the other.

## 3. Software Requirements

1. A program that writes code to memory must execute `FENCE.I` after the store and before running the new code.
2. Software should rely on `FENCE.I` only if the thread will not migrate to another hart, because the instruction affects only the local hart.
3. The reserved fields must be zeroed.

## 4. Multiprocessors and Remote Harts

`FENCE.I` does not ensure that other harts' instruction fetches observe the local hart's stores. To make a store to instruction memory visible to all harts, the writing hart first executes a data `FENCE` and then asks the remote harts to execute `FENCE.I`. The manual adds that the execution environment interface may provide a more efficient mechanism for multiprocessor instruction-stream synchronisation.

## 5. References

| Item | Manual chapter and section |
| :--- | :--- |
| Extension and `FENCE.I` instruction | Chapter 4, section 4.1 |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
