# Zihintpause: Implementation in the Core

This document describes how the Core executes the `pause` hint. The encoding is in [instructions.md](instructions.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 8, Zihintpause Extension for Pause Hint, version 2.0 |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |

## 2. Configuration

| Generic | Default | Effect |
| :--- | :--- | :--- |
| `has_zihintpause` | `false` | Instantiates in the ID stage the decoder that recognizes `pause` |

The `pause` word is a valid `FENCE`, so the core executes it as a `nop` with the generic on or off. When on, the ID stage identifies it as a hint and disables the write to `rd`.

## 3. Decoding in the ID Stage

The decoder claims exactly the word `0x0100000F`, that is, `opcode = 0001111`, `funct3 = 000`, `rd` and `rs1` at `x0`, `fm = 0000`, `pred = 0001` and `succ = 0000`. The other forms of `FENCE` are not claimed.

The pipeline is in order and has a single hart, so there is no other hart to yield resources to, and `pause` inserts no wait.

## 4. Verification

| Level | Coverage |
| :--- | :--- |
| Entity `zihintpause_decode` | The word of the manual, the inversion of each of the 32 bits and other `FENCE` forms, which drop the claim |
| Core | `pause` in sequence with the other hints, no register change and no exception |
| Formal | The decoder claims exactly one word, with three mutants rejected |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
