# Step F.P12: late PC decision, decoded MEM/WB controls and registered load for the dependency check

🌐 [Português](../../pt-br/timing/P12_DECISAO_TARDIA_DO_PC_E_CONTROLES_DECODIFICADOS_EM_REGISTRADOR.md) · [English](P12_DECISAO_TARDIA_DO_PC_E_CONTROLES_DECODIFICADOS_EM_REGISTRADOR.md)

## 1. Summary

| Path | Change | Effect on cycles per instruction |
| :--- | :--- | :--- |
| From the branch comparison in EX, through `pc_src`, the PC enable and the source choice, to the PC register | The taken branch or jump enters only the final selector and the enable of `pc_fetch` (`i_late_take` and `i_late_jalr`), and the `pc_src` and the HDU enable no longer depend on it | None |
| From the two low address bits registered in MEM/WB, through the shift of the word-crossing load and the extender, to the registered write-back data | MEM/WB registers the data position (`o_ext_off`) and the shift with one bit per byte (`o_cross_sel`), and the WB stage joins the words with an AND-OR instead of a shifter | None |
| From `r_re_ram` and the `rd` of ID/EX and EX/MEM, through the load-use comparisons, to the PC enable | ID/EX and EX/MEM register the load bit with `rd` different from `x0` (`o_ld`), and the HDU no longer compares `rd` with zero | None |
| From the branch comparison in EX, through the misaligned-branch address exception, to the counter and CSR writes | The `trap_unit` also delivers the exception without the misaligned-branch one (`o_take_nocf`), and the `csr_file` blocks the CSR writes with it (`i_trap_early`), because a CSR instruction never takes a branch | None |

## 2. Late PC decision

With $t$ the branch or jump decision of EX released by the pipeline and $r$ the priority redirect, the next PC and the enable become

$$ pc' = \begin{cases} pc_{r} & r = 1 \\ pc_{target} & t = 1,\ r = 0 \\ pc_{early} & \text{otherwise} \end{cases} \qquad e = e_{hdu} \lor r \lor t $$

where $pc_{early}$ is the value the four-source selector delivers without the EX decision. Since $t$ arrives last, it feeds only the final target choice and the enable, and the target is the `JALR` one with `i_late_jalr` and the branch or `JAL` one without it. With the branch out of the selection, `pc_src` stays at PC + 4 or at redirect, and the HDU enable no longer includes the branch term.

## 3. MEM/WB decoding

With $o$ the two low address bits and $c$ the word-cross bit, MEM/WB registers

$$ ext\_off = \begin{cases} 0 & c = 1 \\ o & c = 0 \end{cases} \qquad cross\_sel_k = c \cdot [\,o = k\,],\ k \in \{1,2,3\} $$

and the word delivered to the extender is the memory read with $c = 0$ or the join of the read with the first word shifted by $k$ bytes with $cross\_sel_k = 1$. A cross only exists with $o \ne 0$, so the three select bits are never all zero together with $c = 1$.

## 4. Registered load and exception without branch

The load dependency check uses the registered bit $ld = re\_ram \cdot [\,rd \ne x0\,]$ of ID/EX and EX/MEM, so the comparison with zero leaves the path that ends at the PC enable.

The EX exception $trap = early \lor cf$ has a $cf$ part (a taken branch or jump with a misaligned target) that depends on the branch comparison. The counter and machine CSR writes only apply to a CSR instruction, which is never a branch, so they use $early$. The trap entry (`mstatus`, `mepc`, `mcause`) keeps using the full exception.

## 5. Guarantees and how they are verified

| Guarantee | Verification |
| :--- | :--- |
| The PC loads the right target, freezes without enable and gives redirect priority over the late decision | `PcFetch` entity test |
| The join, the extension and the selection of the write-back data are the same | `StageWb` and `RegMemWb` entity tests |
| The load bit and the dependency check hold with and without `rd` equal to `x0` | `RegIdEx`, `RegExMem`, `HazardDetectionUnit` and `StageId` entity tests |
| The exception without branch excludes the misaligned branch and the CSR writes stay blocked by exceptions | `TrapUnit` and `CsrFile*` entity tests, and the formal proofs of the counters and the CSR bank |
| The core keeps its behavior and its cycles | Entity and core tests, formal proofs and Core profiles, with no change in result |

## 6. Measurement

`de0-cv` build in Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT`, fetch and core clocks at 100 MHz with the core phase at 3125 ps, slow-model worst case at 85 °C. The A+B+D column is the sum of PRs #104, #103 and #105, and the last column adds this step to it.

| Seed | A+D (#104 and #105) | A+B+D | A+B+D with this step |
| ---: | :--- | :--- | :--- |
| 1 | +0.089 ns | -0.386 ns | +0.419 ns and +0.528 ns at 0 °C (104.37 MHz) |
| 2 | +0.290 ns | -0.184 ns | +0.450 ns and +0.473 ns at 0 °C (104.71 MHz) |
| 3 | -0.441 ns | -0.356 ns | +0.138 ns and +0.134 ns at 0 °C (101.40 MHz) |
| 4 | +0.116 ns | +0.265 ns | +0.501 ns and +0.467 ns at 0 °C (105.27 MHz) |
| 5 | -0.062 ns | -0.586 ns | +0.358 ns and +0.446 ns at 0 °C (103.71 MHz) |
| Mean at 85 °C | -0.002 ns | -0.249 ns | +0.373 ns |

The SDRAM controller stays above +2.1 ns, `DRAM_CLK` above +0.6 ns and the minimum hold above +0.25 ns in the slow model and +0.06 ns in the fast one, in every seed.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
