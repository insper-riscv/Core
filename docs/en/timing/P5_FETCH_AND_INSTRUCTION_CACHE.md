# Step F.P5: fetch loop and instruction cache

🌐 [Português](../../pt-br/timing/P5_BUSCA_E_CACHE_DE_INSTRUCOES.md) · [English](P5_FETCH_AND_INSTRUCTION_CACHE.md)

## 1. Summary

| | |
| :--- | :--- |
| Problem | The loop PC, instruction cache, PC added up to about 12 ns of data: the PC reached the valid bit of the cache through a one-input-per-line multiplexer, reached the cache select through address comparisons, and the tag read reached the PC enable through six logic levels |
| Change 1 | The valid bit moves to a RAM read with the address of the tag and data RAMs; invalidation becomes a sweep of one line per cycle, with lookups blocked (`icache`, Memory) |
| Change 2 | The cache select comes from the address registered inside the cache (generic `sel_from_kib`), not from decoding the PC in the core |
| Change 3 | A hit is the conjunction of an early part (select, no sweep, address unchanged) with the two late reads (valid and tag), and the PC enable is one gate away from `i_ic_ready` (`stage_if`) |
| Effect on cycles per instruction | None in programs without `fence.i`; each `fence.i` and each region invalidation costs the sweep (256 fetch cycles on the 4 KB cache) |

The counter mechanism the plan cites for this step (`mcycle` in the PC enable) does not exist in the current core: the PC enable depends on the cache, the HDU and the EX decisions, and the Zicntr counters live in the EX domain itself.

## 2. Guarantees and how they are checked

| Guarantee | Check |
| :--- | :--- |
| Nothing the cache holds is older than the last invalidation, and a region leaves no stale data in its lines | Formal proof of the `icache` (Memory), with mutants that remove the block, the sweep and the address check |
| Zihpm events 5 to 7 count the same accesses | Core entity tests and Insper-RISC-V platform tests |
| The PC enable is the same function | Equivalence by construction: $hdu \wedge \neg(sdram \wedge \neg ready) = hdu \wedge \neg sdram \vee hdu \wedge sdram \wedge ready$; entity and platform tests |

## 3. Measurement

The values are in [docs/en/platform/timing/FRENTE-F-ONDA2.md of Insper-RISC-V](../../../../docs/en/platform/timing/FRENTE-F-ONDA2.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
