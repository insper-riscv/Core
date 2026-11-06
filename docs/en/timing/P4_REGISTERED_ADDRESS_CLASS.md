# Step F.P4: effective-address class registered in EX/MEM

🌐 [Português](../../pt-br/timing/P4_CLASSIFICACAO_DO_ENDERECO_REGISTRADA.md) · [English](P4_REGISTERED_ADDRESS_CLASS.md)

## 1. Summary

| | |
| :--- | :--- |
| Problem | In MEM, the region of the address (FLASH, SDRAM, main memory, same region for the two words of a crossing access) was decoded from `r_alu_out` and from the address of the second word, and the result fed the access exception, the misaligned-access stall, the SDRAM stall and, through them, the enable and the clear of the pipeline registers |
| Change | The class comes out of the ALU result in EX and is registered in EX/MEM (`o_is_flash`, `o_is_sdram`, `o_in_main`, `o_same_region`); `stage_mem`, `misaligned_unit` and the MEM `trap_unit` start from the registered bits (generics `flags_registered` and `ea_flags_external`) |
| Effect on behavior | None: the class is the same, one stage earlier |
| Effect on cycles per instruction | None |

## 2. Path before and after

| Step | Before | After |
| :--- | :--- | :--- |
| Origin of the class | 32-bit comparisons on `r_alu_out` and on the address of the second word (`cross` in front) | EX/MEM registers loaded from the ALU output |
| Chain in MEM | Comparisons, cause merge, `cross`, SDRAM decode, stall, pipeline enables | Cause merge over registered bits, stall, pipeline enables |
| Source in EX | Does not exist | ALU output (`o_alu_result` of `stage_ex`), not the final result, so it does not inherit the CSR read |

The address of the second word of a crossing access is in the same region as the first whenever the access is executed, because the MEM `trap_unit` raises the exception when the two words are not in the same region.

## 3. Guarantees and how they are checked

| Guarantee | Check |
| :--- | :--- |
| The registered class is that of the EX address and is cleared on flush and reset | `RegExMem` test (`test_address_class_is_registered`) |
| Each cause and each region of the `trap_unit`, with the region bits coming from outside | Formal proofs of the `trap_unit` and entity tests of `stage_mem` and `misaligned_unit` (decoded path) |
| The whole pipeline stays precise | Core entity tests (`CoreMemTrapEx`, `CoreMisalignedHalf` and the suite), the profiles of `make profiles` |

## 4. Measurement

`de0-cv` build (full profile) in Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT` mode, seed 1, slow model at 85 °C, fetch and core clocks at 83.333 MHz with the core phase at 6000 ps. The full values are in [docs/en/platform/timing/FRENTE-F-ONDA2.md of Insper-RISC-V](../../../../docs/en/platform/timing/FRENTE-F-ONDA2.md).

| Clock pair | Before (ns) | After (ns) |
| :--- | ---: | ---: |
| core to core, worst slack | -0.639 | -0.289 |

## 5. Cost in cycles per instruction

None, because the class is the same and the cycle in which the stall and the exception happen does not change.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
