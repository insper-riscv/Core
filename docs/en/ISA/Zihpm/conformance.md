# Zihpm conformance

This document checks each Zihpm requirement, in [instructions.md](instructions.md), against the behavior of the Core, in [description.md](description.md), and points to the evidence of each line.

## 1. Legend

| Status | Meaning |
| :--- | :--- |
| Conformant | The Core meets the requirement and the evidence shows it |
| EEI choice | The manual leaves the choice to the implementation, and the choice of the Core is recorded |

## 2. Matrix

| ID | Requirement | Status | How the Core meets it | Evidence |
| :--- | :--- | :--- | :--- | :--- |
| K5 | `hpmcounter3` to `hpmcounter31` and their upper halves exist as read-only CSRs | Conformant | With `HAS_ZIHPM` the 29 indices exist in the `0xC00` and `0xC80` ranges, with `hpm_counters` real counters | Test `CsrFileZihpmFull`, proof `csrh29_safety`, program `hpm-sweep` |
| K6 | An unimplemented counter may raise an illegal instruction or read a constant | EEI choice | An index without a counter reads zero and ignores the write, without an exception | Test `CsrFileZihpmReduced`, proof `csrh_safety`, program `hpm-sweep`, Sail model and ACT4 with the counter outside the mask |
| K7 | What each counter counts is defined by the platform and chosen by a register | Conformant | `mhpmeventK` holds a 4-bit code, code 0 does not count and the event table is documented | Test `HpmCounterBankAll64`, programs `hpm-inhibit-select` and `hpm-fused-high` |
| K8 | Zihpm depends on Zicsr | Conformant | The profile matrix implies `HAS_ZICSR` and the elaboration of `core` fails without it | `make profiles` and the assertion of `core` |
| K9 | `mcountinhibit` inhibits `cycle`, `instret` and the event counters | Conformant | Bits 0 and 2 inhibit `mcycle` and `minstret`, bits 3 to $2+$`hpm_counters` inhibit the event counters and the other bits read zero | Tests `CsrFileZihpmFull` and `CsrFileZihpm`, proof `csrh2_safety`, program `hpm-sweep` |

## 3. Requirements of the privileged volume

| Requirement | Status | How the Core meets it | Evidence |
| :--- | :--- | :--- | :--- |
| `mhpmcounter3` to `mhpmcounter31` (`0xB03` to `0xB1F`) are 29 WARL counters of 64 bits, and the address exists even if the counter is fixed at zero | Conformant | 29 addresses always present with `HAS_ZIHPM`; the first `hpm_counters` count and the others read zero | Proof `csrh29_safety`, test `CsrFileZihpmFull` |
| `mhpmcounter3h` to `mhpmcounter31h` (`0xB83` to `0xB9F`) are the upper halves on RV32 | Conformant | The same 29 indices and the same real counters | Proof `csrh29_safety` |
| `mhpmevent3` to `mhpmevent31` (`0x323` to `0x33F`) are WARL selectors, and event 0 means none | Conformant | 4-bit code, the upper bits read zero and an index without a counter reads zero | Test `HpmCounterBankAll64`, proof `csrh_safety` |
| `hpmcounterN` and `hpmcounterNh` mirror the machine counters on reads | Conformant | The mirror range uses the same read selection, and a write is illegal at any index | Test `CsrFileZihpmFull`, mutant `hpm_mirror_writable` |
| Bits 3 to 31 of `mcountinhibit` inhibit each counter, bit 1 is zero | Conformant | One bit per real counter, the other bits read zero | Proof `csrh2_safety`, mutant `hpm_inhibit_reserved_bits` |
| An explicit write to a counter in the same cycle as the event wins | Conformant | The write to each half wins over the increment of the cycle, in all real counters | Proofs of `counter64` and `csrh29_safety`, entity test of the bank |
| A 64-bit read high, low, high recovers a valid value | Conformant | The carry is registered, and the high half read already adds the pending carry | Proofs of `counter64` with widths from 1 to 64 bits, program `hpm-sweep` |
| The counter has 64 bits | EEI choice | `hpm_width` from 0 to 64 bits per profile; the bits above the width read zero | Proofs of `counter64` and `csrh2_safety`, tests `Counter64Width20` to `Counter64Width63` |
| An event code with no meaning counts zero | Conformant | Codes outside the event table never count | Mutant `hpm_event_table_ignored`, entity test of the bank |
| The addresses the chapter does not define inside the ranges are illegal | Conformant | `0x321`, `0x322`, `0xB01` and `0xB81` raise an illegal instruction | Proof `csrh29_safety`, mutant `hpm_range_overlap` |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
