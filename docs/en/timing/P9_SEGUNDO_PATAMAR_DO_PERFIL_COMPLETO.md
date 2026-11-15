# Step F.P9: second-tier paths of the full profile

🌐 [Português](../../pt-br/timing/P9_SEGUNDO_PATAMAR_DO_PERFIL_COMPLETO.md) · [English](P9_SEGUNDO_PATAMAR_DO_PERFIL_COMPLETO.md)

## 1. Summary

| Path | Change | Effect on cycles per instruction |
| :--- | :--- | :--- |
| Data memory address in MEM, which waited for the misaligned access unit | The word crossing is decided in EX and registered in `EX/MEM` (`o_cross` of `reg_ex_mem`); `misaligned_unit` only combines the bit with the valid bit | None |
| Write of `mepc`, `mcause` and `mtval` from the ALU and from MEM | `csr_file` keeps the PC, cause and fault value of the trap in registers and writes the three CSRs one cycle later; `MIE` and `MPIE` change on the edge of the trap itself | None |
| Read of the Zihpm counters | The bank registers the word of each range chosen by the index, and the join by the selections of the instruction is left to the next cycle, the one of the existing `o_csr_wait` wait | None |

## 2. Write of the trap CSRs

A trap taken in cycle $t$ discards the content of `ID/EX`, so the instruction in EX in cycle $t+1$ is a bubble. In that cycle the trap registers write `mepc`, `mcause` and `mtval`, and the result holds from cycle $t+2$. No CSR read or write, other trap or `MRET` falls between the two cycles, and the PC redirect uses `mtvec`, which does not depend on the write.

| Instruction | Earliest cycle that reads `mepc`, `mcause` or `mtval` |
| :--- | :--- |
| First of the handler | $t+3$ |
| `MRET` of the handler | $t+3$ or later |

## 3. Verification

| Guarantee | Verification |
| :--- | :--- |
| `mepc`, `mcause` and `mtval` hold two cycles after the trap | Formal proofs `csr_file_props` (property 4) and `stage_ex_irq_props`, assuming a bubble in the cycle after the trap |
| The registered crossing is what the unit computed in MEM | Core tests of the misaligned access (`cores/misaligned*`) and entity test `RegExMem` |
| The Zihpm bank read returns the value of the address cycle | Entity tests `HpmCounterBankRegistered` and the Zihpm core tests |
| The core behaves the same | Every core test (`cores/`), with the same cycle count and the same final RAM content as before the change |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
