# Sscofpmf conformance

This document checks each requirement of the Sscofpmf extension (chapter 14 and sections 3.1.9 and 3.1.10 of the privileged volume) against the behavior of the Core, in [description.md](description.md), and points to the evidence of each row.

## 1. Legend

| Status | Meaning |
| :--- | :--- |
| Conforming | The Core meets the requirement and the evidence shows it |
| EEI choice | The manual leaves the choice to the implementation, and the choice of the Core is recorded |
| Not applicable | The requirement belongs to a mode the Core does not have (S, U, VS or VU) |

## 2. Matrix

| ID | Requirement | Status | How the Core meets it | Evidence |
| :--- | :--- | :--- | :--- | :--- |
| O1 | `mhpmeventnh` exists for the 29 counters, with `OF` at bit 31 | Conforming | `0x720 + K` with `K` from 3 to 31, with `has_sscofpmf` | Test `CsrFileSscofpmf`, proof `csrof_safety` |
| O2 | `OF` is set when the counter overflows and only a program write clears it | Conforming | The `o_wrap` pulse sets `OF`, and the overflow wins over a simultaneous write | Proof `csrof_safety`, mutants `ofp_of_not_sticky` and `ofp_overflow_loses_to_write` |
| O3 | The overflow is the unsigned overflow of the implemented bits, and a write does not overflow | Conforming | `o_wrap` marks the increment from all ones to zero, for every width | Proof `counter64_props`, tests `CsrFileSscofpmf` and `CsrFileSscofpmfWide`, program `irq-lcofi` |
| O4 | With `OF` at `1` the overflow asks for no interrupt, and `OF` disables the interrupt | Conforming | The request is `o_wrap` and not `OF` | Mutant `ofp_request_ignores_of`, program `irq-lcofi` |
| O5 | The request is local interrupt 13, with `LCOFIP` in `mip` and `LCOFIE` in `mie` | Conforming | Bit 13 of `mip` (read and write) and of `mie` | Proof `csrof_safety` and mutants `ofp_lcofip_write_lost` and `ofp_lcofie_ignored` |
| O6 | `LCOFIP` is cleared by the program before servicing the interrupt | Conforming | A write to `mip` with bit 13 at `0` | Program `irq-lcofi` |
| O7 | The priority is the lowest of the machine interrupts | Conforming | After external, software and timer | Proof `csrof_safety`, mutant `ofp_lcofi_before_timer`, program `irq-lcofi-priority` |
| O8 | The request reaches `mip` in bounded time, "eventually, not necessarily immediately" | EEI choice | `OF` and `LCOFIP` show up two cycles after the overflowing increment | Proof `csrof_safety` |
| O9 | `MINH` inhibits counting in the mode whose bit is `1` | Conforming | `MINH` (bit 30) inhibits counting in machine mode | Test `CsrFileSscofpmf`, mutant `ofp_minh_ignored`, program `irq-lcofi` |
| O10 | `SINH`, `UINH`, `VSINH` and `VUINH` are read-only zero without the matching mode | Conforming | Bits 29 to 26 read zero | Test `CsrFileSscofpmf` |
| O11 | `scountovf` reflects the `OF` bits for S-mode | Not applicable | The Core has no S-mode, and `0xDA0` is a nonexistent address | Test `CoreTrapPriority` |
| O12 | Delegation of bit 13 by `mideleg` | Not applicable | The Core has neither S-mode nor `mideleg` | Test `CoreTrapPriority` |
| O13 | Without the extension, `LCOFIP` and `LCOFIE` are read-only zero and `mhpmeventnh` does not exist | Conforming | Zero constants and nonexistent addresses without `has_sscofpmf` | Test `CsrFileSscofpmfOff`, proofs `csri_safety` and `csrh_safety` |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
