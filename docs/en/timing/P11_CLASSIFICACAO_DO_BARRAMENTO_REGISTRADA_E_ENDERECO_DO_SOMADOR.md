# Step F.P11: registered bus classification and effective address from the adder

🌐 [Português](../../pt-br/timing/P11_CLASSIFICACAO_DO_BARRAMENTO_REGISTRADA_E_ENDERECO_DO_SOMADOR.md) · [English](P11_CLASSIFICACAO_DO_BARRAMENTO_REGISTRADA_E_ENDERECO_DO_SOMADOR.md)

## 1. Summary

| Path | Change | Effect on cycles per instruction |
| :--- | :--- | :--- |
| From the MEM address, through the comparison with the FLASH and RAM windows of the interconnect, to the core `ready` and from there to `pipe_run` | The classification of the access as a bus memory leaves EX registered in `EX/MEM` (`o_is_bus_mem`) and the core delivers it on the `o_ext_is_mem` port; the interconnect uses it in place of the address comparison | None |
| From the final ALU result, through the shifters and the OR select, to the region bits registered in `EX/MEM` | The effective address of a load or store comes straight from the ALU adder (`o_sum`), which is the operation of every memory access, and from it come the region classification, the word-cross decision and the byte offset of the `store_manager` | None |

## 2. Registered bus classification

The core knows only the BOOT_MEMORY, the FLASH and the RAM, and already registered the region of the access in EX. With $F$ and $R$ the FLASH and RAM windows, and $f_b$ and $r_b$ the generics `FLASH_ON_BUS` and `RAM_ON_BUS`, the new bit is

$$ b = f_b\,[\,a \in F\,] + r_b\,[\,a \in R\,] $$

over the effective address $a$, and it is what the interconnect decided by comparing the MEM address with the same windows. The interconnect no longer decodes the address to choose between the `ready` of the bus memory and its own, and the `ready` that reaches the MEM stage, and from there `pipe_run` and the Zihpm events, comes from a registered bit.

Outside an access the bit does not matter, as the comparison did not. A misaligned access that crosses the word uses the same bit for the second word, because it only crosses inside the region (`o_same_region`).

## 3. Effective address from the adder

The ALU delivers the final result after the shift and the OR select of the operations. The effective address $a = r_{s1} + imm$ is the output of the adder, and it now goes to the region registers, to the word-cross computation and to the `store_manager` without passing through the shifters or the select.

## 4. Guarantees and how they are verified

| Guarantee | Verification |
| :--- | :--- |
| The registered bit is the classification of the address, at every region-edge address, with the FLASH on the bus and off it | Entity tests `RegExMemAddrOk` and `RegExMemAddrOkFlashBus`, against a model of the windows |
| The direct sum is the sum of A and B | Entity test `ALU`, which checks `o_sum` in every addition |
| The interconnect with the port receives the same bit that the comparison would give | Simulation assertion in the interconnect on every access, in the platform tests of Insper-RISC-V |
| The core keeps its behavior and cycles | Entity and core tests, formal proofs and profiles of the Core, with no change of result |

## 5. Measurement

`de0-cv` build in Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT`, fetch and core clocks at 100 MHz with the core phase at 3125 ps, worst case of the slow model at 85 °C, with PR #104 as the start.

Core slack (ns) in the slow model, at 85 °C and at 0 °C, and Fmax at 85 °C, with A the PR #104, A+D the #104 with this step, A+B the #104 with the #103 and A+B+D the three together.

| Seed | A | A+D | A+B | A+B+D |
| ---: | :--- | :--- | :--- | :--- |
| 1 | -0.630 and -0.306 (94.07 MHz) | +0.089 and +0.263 (100.90 MHz) | -0.127 and -0.006 (98.75 MHz) | -0.386 and -0.267 (96.28 MHz) |
| 2 | -0.753 and -0.645 (93.00 MHz) | +0.290 and +0.437 (102.99 MHz) | -0.055 and -0.021 (99.45 MHz) | -0.184 and -0.011 (98.19 MHz) |
| 3 | +0.052 and +0.144 (100.52 MHz) | -0.441 and -0.369 (95.78 MHz) | -0.377 and -0.210 (96.37 MHz) | -0.356 and -0.107 (96.56 MHz) |
| 4 | -0.512 and -0.392 (95.13 MHz) | +0.116 and +0.293 (101.17 MHz) | -0.488 and -0.398 (95.35 MHz) | +0.265 and +0.401 (102.72 MHz) |
| 5 | -0.107 and -0.011 (98.94 MHz) | -0.062 and +0.009 (99.38 MHz) | -0.399 and -0.533 (96.16 MHz) | -0.586 and -0.251 (94.46 MHz) |
| Mean at 85 °C | -0.390 | -0.002 | -0.289 | -0.249 |

The gain over the #104 is 0.39 ns on average and closes the setup at 85 °C in three of the five seeds (1, 2 and 4), and seed 5 stays at -0.062 ns. Over the #104 with the #103 the mean changes little, because the critical path becomes the branch resolution in EX (forwarding select, comparison and PC redirect) and the counter write, and the spread between seeds (0.2 to 0.4 ns) is the size of the gain. In seeds 3 and 5 the worst path of A+D leaves MEM/WB toward the write-back data of the previous instruction. The SDRAM controller stays above +1.9 ns, `DRAM_CLK` above +0.6 ns and the minimum hold above +0.06 ns in every seed of A+D.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
