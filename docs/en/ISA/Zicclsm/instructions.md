# Zicclsm: What RISC-V Requires

Zicclsm is not part of the unprivileged ISA manual. It is defined in the RISC-V profiles specification, as one of the requirements that a profile places on main memory. This document gathers what that specification requires, what the ISA manual says about misaligned accesses in general, and how this relates to the misaligned address exceptions. The Core implementation is in [description.md](description.md).

## 1. Profile Requirement

### 1.1. Definition

The profiles specification defines Zicclsm as the requirement that misaligned loads and stores to main memory regions that have the cacheability and coherence physical memory attributes (PMAs) be supported. The normative text says only "misaligned loads and stores", without qualification, which includes regular loads and stores, scalar and vector. What counts as a misaligned access in a vector load or store is defined by the vector specification.

### 1.2. Profiles That Require It

| Profile | Section of the profiles specification |
| :--- | :--- |
| RVA20U64 | RVA20U64 Mandatory Extensions |
| RVA22U64 | RVA22U64 Mandatory Extensions |
| RVA23U64 | RVA23U64 Mandatory Extensions |

The RVA20S64, RVA22S64 and RVA23S64 profiles include all the mandatory unprivileged extensions of the corresponding user profile. The list of new extensions of the profiles specification summarises Zicclsm as "Main memory supports misaligned loads/stores".

### 1.3. Non-Normative Notes

The notes that accompany the definition do not change its meaning. They clarify the points below.

| Point | Content of the note |
| :--- | :--- |
| Extension name | Zicclsm is a new name for an already existing feature |
| Coverage | The requirement applies to the regular load and store instructions, and not to AMOs or other specialised forms of memory access |
| Performance | A misaligned access may run extremely slowly, and standard software should assume its existence only for correctness, never for performance |

## 2. What the ISA Manual Says About Misaligned Accesses

The unprivileged ISA volume covers the topic in the Load and Store Instructions section, in the RV32I base chapter. The relevant points are the following.

| Aspect | Rule of the manual |
| :--- | :--- |
| Aligned access | A load or store with a naturally aligned effective address never raises an address-misaligned exception, regardless of the execution environment interface (EEI) |
| Misaligned access | The behaviour depends on the EEI. An address is misaligned when it is not divisible by the access size in bytes |
| EEI that guarantees support | Software never sees a misalignment exception, and the access may be handled in hardware, by a trap invisible to the execution environment, or by a combination of both depending on the address |
| EEI that does not guarantee support | The access may complete or raise an exception. The exception may be an address-misaligned or an access-fault exception, and the latter is allowed when the access should not be emulated, for example if the region has side effects |
| Exception kind | When support is not guaranteed, the EEI defines whether the exception is contained (handled by software) or fatal |
| Performance | Even when it completes, a misaligned access may be extremely slow, for example if it is implemented through an invisible trap |
| Atomicity | Naturally aligned loads and stores are atomic, and misaligned ones may not be, so software needs additional synchronisation when it requires atomicity |

For the regions it covers, Zicclsm requires support for misaligned accesses, which corresponds to the case of the manual in which the EEI guarantees that support.

## 3. Relation to the Misaligned Address Exceptions

The privileged ISA manual defines the `mcause` cause codes for misaligned accesses, according to the exception code table of the Machine Cause Register section.

| Code | Cause |
| :--- | :--- |
| 4 | Load address misaligned |
| 6 | Store/AMO address misaligned |

A misaligned access that the implementation does not run raises one of these exceptions, and the manual allows an access fault in place of cause 4 or 6 when the access should not be emulated.

## 4. Scope Considered in the Core

The specification covers regular loads and stores, scalar and vector, and excludes AMOs. The Core implements the scalar RV32I loads and stores (`LB`, `LBU`, `LH`, `LHU`, `LW`, `SB`, `SH` and `SW`), without vectors and without AMOs. The map the Core adopts as main memory for that purpose is in [description.md](description.md).

## 5. Sources

| Document | Section |
| :--- | :--- |
| RISC-V Profiles (repository `riscv/riscv-profiles`, files `profiles.adoc` and `rva23-profile.adoc`) | RVA20U64 Mandatory Extensions, RVA22U64 Mandatory Extensions, RVA23U64 Mandatory Extensions and the list of new extensions |
| Clarification by the editors of the profiles specification (issue 202 of the same repository, closed on 2026-03-21) | Normative text without qualification, with non-normative notes |
| The RISC-V Instruction Set Manual, Volume I (Unprivileged Architecture) | RV32I Base Integer Instruction Set chapter, Load and Store Instructions section |
| The RISC-V Instruction Set Manual, Volume II (Privileged Architecture) | Machine-Level ISA, Machine Cause Register section |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
