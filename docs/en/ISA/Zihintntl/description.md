# Zihintntl: Implementation in the Core

This document describes how the Core executes the four `Zihintntl` hints. The encodings are in [instructions.md](instructions.md).

## 1. Configuration

| Generic | Default | Effect |
| :--- | :--- | :--- |
| `has_zihintntl` | `false` | Instantiates in the ID stage the decoder that recognizes the four hints |

A hint is a valid `ADD` to `x0`, so the core executes it as a `nop` with the generic on or off. The difference is that, when on, the ID stage identifies the word as a hint and disables the write to `rd`, so no destination register reaches the following stages.

## 2. Decoding in the ID Stage

The decoder claims a word when every condition in the table holds.

| Field | Value |
| :--- | :--- |
| `opcode` | `0110011` |
| `funct3` | `000` |
| `funct7` | `0000000` |
| `rd` and `rs1` | `x0` |
| `rs2` | `x2` to `x5` |

A claimed word does not enable the write to `rd`. The Core has no cache hierarchy with locality domains, so the hint changes nothing else.

## 3. Verification

| Level | Coverage |
| :--- | :--- |
| Entity `zihintntl_decode` | The four words of the manual, every value of `rs2` and the inversion of each fixed bit, which drops the claim |
| Core | The five hints (with `pause`) in sequence, with the registers read right after, no register change and no exception |
| Formal | The decoder claims exactly the four encodings, with five mutants rejected |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
