# Sscofpmf in the Core

This document describes how the Core implements the Sscofpmf extension (count overflow and mode-based filtering) for a hart that has machine mode only. The conformance of each requirement is in [conformance.md](conformance.md), the event counters are in [Zihpm](../Zihpm/description.md) and the interrupt entry is in [Zicsr](../Zicsr/description.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 14, "Sscofpmf" Extension for Count Overflow and Mode-Based Filtering, version 1.0 |
| Source | Volume II of the RISC-V manual (privileged ISA, version 20260120), sections 3.1.9, 3.1.10 and 14.1 |
| Conformance of the Core with the privileged volume | `docs/conformance/riscv-privilegiado.md` of Insper-RISC-V |

## 2. Parameters

| Parameter | Entity | Default | Effect |
| :--- | :--- | :--- | :--- |
| `HAS_SSCOFPMF` | `core` | `false` | Turns the extension on; needs `HAS_ZIHPM` and `HAS_INTERRUPTS` |

Elaboration fails if `HAS_SSCOFPMF` is on without the other two. The platform profile turns the extension on with `extras: [Sscofpmf]` in `platform.yaml`, which `riscv-tools` turns into `HAS_SSCOFPMF` in the VHDL package of the memory map. The extension is not part of the profile matrix of the Core, like the machine interrupts.

## 3. What the extension adds

The Core has machine mode only, so the parts of the extension that depend on the S, U, VS and VU modes do not exist: the `SINH`, `UINH`, `VSINH` and `VUINH` fields of the event selector read zero, and `scountovf` (`0xDA0`) is a nonexistent address.

| Item | Position | Effect |
| :--- | :--- | :--- |
| `mhpmeventKh` | $0x720 + K$, $K$ from 3 to 31 | Upper half of the event selector of counter $K$ |
| `OF` | Bit 31 of `mhpmeventKh` | Overflow of counter $K$, which only a program write clears; with `OF` at `1` a new overflow asks for no interrupt |
| `MINH` | Bit 30 of `mhpmeventKh` | Inhibits event counting in machine mode, the only mode of the Core |
| `LCOFIP` | Bit 13 of `mip` | Overflow interrupt request, read and write |
| `LCOFIE` | Bit 13 of `mie` | Enables the overflow interrupt |
| Cause | `mcause` = `0x8000000D` | Interrupt 13, local counter overflow (LCOFI) |

The other bits of `mhpmeventKh` read zero and ignore writes. An index with no real counter (`hpm_counters`) reads zero and ignores writes to `mhpmeventKh`, without an exception, like the other Zihpm CSRs. Addresses `0x720` to `0x722` and `0x740` upward stay nonexistent.

## 4. Counter overflow

The overflow is the increment that takes the whole counter of `hpm_width` bits from all ones to zero. A write to the counter or to the selector never overflows. The counter block (`counter64`) delivers an `o_wrap` pulse in the cycle after the increment, and the Zihpm bank handles the pulse this way.

| State at the pulse | `OF` | `LCOFIP` |
| :--- | :---: | :---: |
| `OF` at `0` | Becomes `1` | Becomes `1` |
| `OF` at `1` | Stays at `1` | Unchanged |

The overflow wins over a write that clears `OF` in the same cycle. `LCOFIP` is cleared by the program, with a write to `mip` with bit 13 at `0`, and a write to `mip` in the cycle of a request does not lose it. The `OF` bit also works as the interrupt disable of the counter, so a program that wants the interrupt clears `OF` together with the initial value of the counter.

The counter overflows only through an increment: `mcountinhibit` and `MINH` stop the increment and, as a consequence, the overflow.

## 5. Interrupt

`LCOFIP` and `LCOFIE` enter the general taking condition of section 7 of [Zicsr](../Zicsr/description.md): the interrupt is taken with `mstatus.MIE` at `1` and `LCOFIP` and `LCOFIE` at `1`. The priority is the manual one, the lowest among the machine interrupts, after external, software and timer. In the vectored mode of `mtvec` the interrupt goes to $BASE + 4 \times 13 = BASE + 52$, and the 64-byte alignment of `BASE` in that mode holds cause 13.

## 6. Structure

| Block | Role |
| :--- | :--- |
| `counter64` | Generates the `o_wrap` overflow pulse |
| `hpm_counter_bank` | Keeps `OF` and `MINH` per counter, applies `MINH` to the counting and gathers the request in `o_ovf_irq` |
| `csr_file` | Decodes `mhpmeventKh`, keeps `LCOFIP` and `LCOFIE`, and joins the request to `o_irq_pending`, `o_irq_take` and `o_irq_cause` |

With `HAS_SSCOFPMF = false` the `csr_file` fixes `LCOFIP` and `LCOFIE` at zero, the `0x720` range is nonexistent and the bank does not instantiate `OF` or `MINH`.

## 7. Verification

| Guarantee | Evidence |
| :--- | :--- |
| The addresses and bit 13 exist only with the extension | Tests `CsrFileSscofpmf`, `CsrFileSscofpmfWide` and `CsrFileSscofpmfOff` |
| The overflow sets `OF` and `LCOFIP` once, with `OF` at `1` it asks nothing, a write does not overflow, `MINH` stops the counting, the timer goes before the overflow | The same tests and the `csr_ofp_props` proof with eight mutants |
| The `o_wrap` pulse is the ideal overflow of the previous cycle, for every width | Proof `counter64_props` and the mutants `wrap_without_hi` and `wrap_on_lo_write` |
| The interrupt is taken with cause 13 and goes to `BASE + 52` | Programs `irq-lcofi` and `irq-lcofi-priority` of the Tests repository |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
