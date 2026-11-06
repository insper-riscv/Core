# Zifencei: Core Implementation

The `FENCE.I` instruction synchronises the instruction stream with the earlier stores of the same hart. After it, an instruction fetch sees everything the program wrote to memory before. What the RISC-V manual requires is in [instructions.md](instructions.md). This document describes what it is for, how the Core executes it and what happens in the pipeline and in the caches.

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 4, Zifencei Extension for Instruction-Fetch Fence, version 2.0 |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |

## 2. What It Is For

Instruction fetch and stores use different paths. The instruction cache only reads memory and does not observe the hart's stores. A program that writes new code and jumps to it therefore needs a step that makes the write visible to the fetch.

| Situation | Without `FENCE.I` | With `FENCE.I` |
| :--- | :--- | :--- |
| The instruction cache holds the old line of the written address | The fetch executes the old code | The line is discarded and the fetch reads the new code |
| A store is still in the write-back data cache | The memory does not have the new code | The store is written to memory before the invalidation |

Typical cases are a loader that copies a program into memory, code generation at run time and the replacement of a routine in use.

## 3. Where the Instruction Has Effect

Only code fetched through the instruction cache is affected. The BOOT_ROM is read directly, and the internal ROM and internal RAM do not go through the cache either. A fetch goes through the instruction cache when the address outside the BOOT_ROM is external: it belongs to the external window from `ext_base_kib`, to a ROM flagged `rom_external`, or to a RAM flagged `ram_external`. The limits come from the generics described in [02-barramento-e-memoria.md](../../contracts/02-barramento-e-memoria.md).

| Fetch region | Goes through the instruction cache |
| :--- | :--- |
| BOOT_ROM | No |
| ROM with `rom_external` false | No |
| ROM with `rom_external` true | Yes |
| RAM with `ram_external` true | Yes |
| External window from `ext_base_kib` | Yes |

In the default map (`rom_external` false) the ROM is internal and read directly, so only code written to the external window (from `0x40000000`) changes its result with `FENCE.I`. With an external ROM, `FENCE.I` also applies to code written to it.

## 4. Configuration

Two Core parameters decide the behaviour.

| Parameter | Meaning |
| :--- | :--- |
| `has_zifencei` | Enables the extension. It is enabled by the profiles whose name includes `zifencei` |
| `has_dcache` | Indicates a write-back data cache, which requires a flush before the invalidation |

| `has_zifencei` | Behaviour of `FENCE.I` |
| :--- | :--- |
| False | Illegal instruction, with an exception of cause 2 when there is Zicsr |
| True | Executes as in sections 4 and 5 |

The ordinary `FENCE` instruction, with `funct3 = 000`, is not handled by this unit and behaves as a `NOP`.

The decoder recognises `FENCE.I` by the `MISC-MEM` opcode and `funct3 = 001`, and ignores the `rd`, `rs1` and `funct12` fields, as the manual requires of base implementations.

## 5. Execution Without a Data Cache

Without a write-back data cache, the stores are already in memory when they leave the MEM stage. `FENCE.I` completes in the same cycle in which it is valid in the EX stage and the pipeline advances. In that cycle the unit emits a completion pulse, which produces the three effects below.

1. Invalidates the instruction cache.
2. Discards the instructions in IF/ID and ID/EX.
3. Redirects the PC to $\text{PC} + 4$, the address of the instruction after `FENCE.I`.

## 6. Execution With a Write-Back Data Cache

With the data cache, the earlier stores may be only in the cache. The unit flushes them before invalidating the instruction cache, because the invalidation only helps if the memory already has the new code.

The unit holds the instruction in EX and uses two flip-flops, one that arms the flush pulse and one that waits for the acknowledgement.

| Cycle | Event | Pipeline |
| :--- | :--- | :--- |
| 0 | `FENCE.I` reaches EX. The store right behind it is still in MEM | Stalled |
| 1 | The earlier stores have reached the cache. The unit emits the flush pulse | Stalled, unless acknowledged in the same cycle |
| 2 onwards | The unit waits for the acknowledgement of the cache | Stalled |
| Acknowledgement cycle | The acknowledgement arrives and the completion pulse goes out | Advances |

The acknowledgement may arrive in the cycle of the flush pulse, for a cache that answers combinationally, or in any later cycle. The completion pulse goes out in the cycle in which the acknowledgement arrives, and produces the same three effects of section 5.

## 7. Effect on the Pipeline

| Element | Effect |
| :--- | :--- |
| PC | Jumps to $\text{PC} + 4$ in the cycle of the completion pulse |
| IF/ID and ID/EX | Emptied, which discards the two instructions already fetched after `FENCE.I` |
| EX/MEM | Receives a bubble while the unit holds the instruction, so the instruction does not advance twice |
| Earlier stages | Frozen while the unit is busy |
| Output to the instruction cache | One-cycle invalidation pulse, in the cycle of the completion pulse |
| Output to the data cache | One-cycle flush pulse, only with `has_dcache` |

The two discarded instructions are fetched again from $\text{PC} + 4$, with the instruction cache already empty.

## 8. Effect on the Caches

| Cache | Operation | Result |
| :--- | :--- | :--- |
| Instruction | One invalidation pulse | Every line is discarded in one cycle. A line still being brought from the SDRAM at the moment of the pulse is discarded too, because it may hold code older than the program's stores |
| Write-back data | One flush request | Every dirty line is written to memory. The lines stay valid and become clean |
| Write-through data | One flush request | The memory already has every completed store and no line is dirty, so the flush writes nothing |

The duration of the flush depends on the data cache, which is external to the Core. It signals completion with a pulse, which the Core uses as the acknowledgement and which may arrive in the cycle of the request or in any later cycle.

## 9. Use in a Program

The correct sequence writes the code, executes `FENCE.I` and only then jumps to it.

```asm
    sw      t1, 0(t0)       # writes the new instruction at t0
    fence.i                 # makes the write visible to the fetch
    jr      t0              # executes the new code
```

An instruction between the store and `FENCE.I` does not change the guarantee. The jump must come after `FENCE.I`, because only after it does the fetch see the new code.

## 10. Cost

| Configuration | Cost of `FENCE.I` |
| :--- | :--- |
| Without a data cache | Two discarded instructions, plus the cache miss on the first external fetch after the invalidation |
| With a data cache | The cache flush time, which the Core waits for with the pipeline stalled, plus the cost above |

The flush happens even without dirty lines, so `FENCE.I` is an expensive instruction with a data cache and should be used rarely.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
