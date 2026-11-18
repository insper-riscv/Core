# Step F.P10: registered address exception and next word

🌐 [Português](../../pt-br/timing/P10_EXCECAO_DE_ENDERECO_E_PALAVRA_SEGUINTE_REGISTRADAS.md) · [English](P10_EXCECAO_DE_ENDERECO_E_PALAVRA_SEGUINTE_REGISTRADAS.md)

## 1. Summary

| Path | Change | Effect on cycles per instruction |
| :--- | :--- | :--- |
| From the MEM `trap_unit` to the data cache write enable | The decision on misalignment and on a store to a read-only region comes from three bits registered in `EX/MEM` (`o_ea_xlast`, `o_ea_unal` and `o_ea_stf`) combined with the region, which is also registered; `stage_mem` and `core` decide the address exception and the validity of the access in that single level of logic (generic `ea_ok_registered`) | None |
| From the registered address to the memory address, through the adder and the selector of the `misaligned_unit` | The word that follows the one of the access is registered in the cycle of step 1 and step 2 selects it, with no adder on the address path; the memory address leaves the unit without the selector by `mis_cross`, because outside step 2 the unit presents the own address of `EX/MEM` | None |

## 2. Address exception

The MEM `trap_unit` still generates the cause and `mtval`. The decision that the access raises an exception, which closed the path to the memory write, now starts from bits decided in EX out of `funct3`, the read and write controls and the two low bits of the effective address, which the ALU adder delivers early. The region bits (`o_in_main`, `o_same_region`, `o_ok_wr`) were already registered.

With $m$ the main memory, $l$ the last word of the region, $x$ the access that crosses the word, $u$ the misaligned access, $s$ the store and $w$ the region that does not accept writes, the address exception is

$$ e = m\,l\,x + \bar{m}\,u + \bar{w}\,s_f $$

with Zicclsm, where $s_f$ is the store with `HAS_ACCESS_FAULTS`. Without Zicclsm, $x$ is replaced by $u$ and the last-word term does not exist. The three registered bits are $x$, $u$ and $s_f$, and all are zero without `HAS_ZICSR`.

| Region of the address | Access that is an exception |
| :--- | :--- |
| Main memory, outside the last word of a region | Only the store to a region that does not accept writes (the FLASH on the bus) |
| Last word of a main memory region | Also the access that crosses the word |
| Outside main memory (BOOT_MEMORY and direct FLASH) | Every misaligned access and every store |

## 3. Next word and memory address

The address of the access is stable in steps 1 and 2 of the `misaligned_unit`. The next word captured at the end of step 1 holds during the whole of step 2, so the address presented to the memory comes out of a multiplexer of registers, not out of the 30-bit adder.

Outside step 2 the unit presents the address of `EX/MEM`, so the memory address is its output without the selector that depended on the address exception.

## 4. Guarantees and how they are checked

| Guarantee | Check |
| :--- | :--- |
| The exception composed from the registered bits is the one of the `trap_unit`, for every `funct3`, control, address byte and region, with the FLASH on the direct port and on the bus | Entity tests `RegExMemAddrOk` and `RegExMemAddrOkFlashBus`, against a model of the exception rules |
| The core stays precise, with the cause and the `mtval` of the `trap_unit` | Formal proofs of the `trap_unit` and of `stage_mem`, core tests of the misaligned access and of the exception in MEM |
| The next word of step 2 is the same as before | Core tests of the misaligned access (`cores/misaligned*`) with the same number of cycles |

## 5. Measurement

`de0-cv` build in Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT`, seed 5, fetch and core clocks at 100 MHz with the core phase at 3125 ps, worst case of the slow model at 85 °C.

| Step | Core slack (ns) | Core Fmax (MHz) |
| :--- | ---: | ---: |
| Start (Core `f61b96d`) | -1.236 | 89.0 |
| Registered address exception | -0.316 | 96.94 |
| With the three registered bits and the registered next word | -0.316 | 96.94 |
| With the memory address without the selector by `mis_cross` | -0.107 | 98.94 |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
