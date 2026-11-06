# Step F.P1: address exception decided in MEM

## 1. Summary

| | |
| :--- | :--- |
| Problem | The address exception of a load or store (misaligned access outside the main memory) depended on the ALU result, and the trap-take signal went from there to the PC, the pipeline registers, the CSRs and the RAM write |
| Change | With Zicsr, the trap unit of the EX stage does not check the effective address; the one in the MEM stage does, over the address registered in EX/MEM |
| Effect on behavior | The exception is taken one stage later, but for an instruction older than the one in EX, so the trap stays precise |
| Effect on the core loop | The exception detection and clearing segments (7.3 ns of an 18.9 ns loop) leave the ALU path |
| Without Zicsr | The EX stage still checks the address and only signals the cause, because there is no CSR to record it and no redirection |

## 2. Path before and after

| Stage | Before | After |
| :--- | :--- | :--- |
| Source of the checked address | Combinational ALU output in EX | `r_alu_out` register of EX/MEM |
| Who decides | `trap_unit` of EX with `check_ea` on | `trap_unit` of MEM with `check_ea` on; the one in EX gets `check_ea` off |
| Chain after the ALU | ALU, region and word-crossing comparison, cause merge, pipeline clearing | None: the ALU ends at the EX/MEM register |
| Chain in the next cycle | Does not exist | Region and word-crossing comparison over the register, cause merge, pipeline clearing |

## 3. Guarantees and how they are verified

| Guarantee | Verification |
| :--- | :--- |
| The failing load or store neither accesses the memory nor writes the destination | `CoreMisalignedHalf` test (loads without effect on the register, stores without effect on the buffer) |
| The next instruction, already in EX, does not commit a CSR, does not write a register or memory and does not count a taken branch | `CoreMemTrapEx` test, eight cases (a failing load or store followed by a CSR write, a store, a register write or a taken branch) |
| `mepc` holds the PC of the failing instruction, `mcause` and `mtval` hold the cause and the address | `CoreMemTrapEx` test |
| `minstret` and the Zihpm counters do not count the failing instruction nor the discarded one | `CoreMemTrapEx` test (the `minstret` difference equals one instruction plus those of the handler) and the `cntr_cancel_ignored` mutant of the `csr_file` formal proof |
| Each cause and each region of the `trap_unit` | `trap_unit` formal proofs, with and without the address check, and with Zicclsm on and off |

The `CoreMemTrapEx` test fails in all eight cases when the discard of the EX instruction is removed (the EX validity stops discounting the MEM trap).

## 4. Measurement

Build of the `de0-cv` (full profile, 29 Zihpm counters) with the RTL of this step, in Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT` mode, seeds 1 to 5, core clock at 50 MHz, slow model at 85 degrees C. The sources are Insper-RISC-V `224a762`, Core `8a828cc`, Memory `1160ae1`, Peripherals `d7253f6` and Common-Components `9aa6a75`; the result files are in `docs/pt-br/platform/timing/dados/` of Insper-RISC-V.

| Clock pair | Worst slack of the five seeds (ns) | Data delay of the worst path (ns) |
| :--- | ---: | ---: |
| core to core | 3.931 | 14.6 to 16.7 |
| core to fetch | 3.403 | 7.9 to 9.2 |
| fetch to core | -1.345 | 4.9 to 5.2 |

| Domain | Setup slack, worst seed (ns) | Fmax, worst seed (MHz) |
| :--- | ---: | ---: |
| Core | -1.345 | 62.23 |
| Fetch | 3.403 | |
| SDRAM controller | -0.744 | 173.28 |
| `DRAM_CLK` | -0.127 | |
| JTAG | 7.612 | 55.22 |

The hold slack in the fast model at 0 degrees C is positive in all domains and seeds, with a minimum of 0.002 ns in the JTAG. The ALMs are 8,058 to 8,095 (44 %).

The core loop (`EX/MEM r_alu_out` and the CSRs to the PC, the pipeline registers and the counters) is no longer the limit: the slack at 50 MHz is positive in all seeds. The limit is the path from the instruction cache tag to the PC (fetch to core), which step F.P5 targets. The worst core-to-core path starts at `ID/EX r_imm`, goes through the CSR read multiplexer (29 event counters) and ends at `mepc`, that is, the CSR read feeds the CSR write through 9 logic levels.

## 5. Cost in cycles per instruction

None. The address exception only occurs in failing programs, and the path without an exception has the same latency.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
