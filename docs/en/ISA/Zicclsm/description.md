# Zicclsm: Core Implementation

Zicclsm is the extension, defined in the RISC-V profiles specification, that requires misaligned loads and stores to run without an exception in main memory. This document describes how the Core executes those accesses and the path a misaligned instruction takes through the pipeline. What the specification requires, with its sources, is in [instructions.md](instructions.md). The `has_zicclsm` generic (default `true`) turns the extension on and off.

## 1. Access Classification

The alignment of an access depends on the width of the instruction and on the two least significant bits of the effective address, the offset $o = \text{ea}[1:0]$.

| Instruction | $o = 0$ | $o = 1$ | $o = 2$ | $o = 3$ |
| :--- | :--- | :--- | :--- | :--- |
| `LB`, `LBU`, `SB` | Aligned | Aligned | Aligned | Aligned |
| `LH`, `LHU`, `SH` | Aligned | Inside the word | Aligned | Crosses the word |
| `LW`, `SW` | Aligned | Crosses the word | Crosses the word | Crosses the word |

| Class | Execution | Cost |
| :--- | :--- | :--- |
| Aligned | One memory access | No extra cycle |
| Inside the word | One access, with the bytes chosen by the offset | No extra cycle |
| Crosses the word | Two accesses to consecutive words | One extra cycle in the internal RAM |

An access that crosses the word occupies the last bytes of a 32-bit word and the first bytes of the next one.

## 2. When the Hardware Executes the Access

For the purpose of the extension, the Core treats as main memory the data regions between the end of the internal ROM (or the external base, when the ROM is external) and the base of the peripheral window. The limits come from the memory map generics (`rom_end_kib`, `rom_external`, `ram_base_kib`, `ram_end_kib`, `ext_base_kib` and `periph_base_kib`), described in [02-barramento-e-memoria.md](../../contracts/02-barramento-e-memoria.md). 

The start of the main memory is `ext_base_kib * 1024` when `rom_external` is true and `rom_end_kib` is 0, and `rom_end_kib * 1024` otherwise. The end is `periph_base_kib * 1024`, where the peripheral window starts. The intervals below are half-open and hold for any value of the generics.

| Region | Range as a function of the generics | Misaligned access in hardware |
| :--- | :--- | :--- |
| Below the main memory (BOOT_ROM, internal ROM and unmapped range) | `[0, start)` | No, raises an exception |
| Main memory | `[start, periph_base_kib * 1024)` | Yes |
| Peripherals | `[periph_base_kib * 1024, 2**32)` | No, raises an exception |

Each platform fixes the generics in its `config.yml`. The table shows the two maps used today, with the main memory and the peripherals already converted to addresses.

| Map | `rom_external` | `rom_end_kib` | `ext_base_kib` | `periph_base_kib` | Main memory | Peripherals |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| Default, with internal RAM | `false` | 32 | 1048576 | 2097152 | `0x00008000` to `0x7FFFFFFF` | `0x80000000` onwards |
| Platform with external FLASH | `true` | 0 | 524288 | 1572864 | `0x20000000` to `0x5FFFFFFF` | `0x60000000` onwards |

A misaligned access that fits in one word (`LH`, `LHU` and `SH` with $o = 1$) is executed when the address is in the main memory. An access that crosses the word is executed only when it meets the two conditions below.

1. The address is in the main memory of the map in use.
2. The address does not belong to the last word of a region. Both words of the access must be in the same region, and the word after the last one of each region belongs to the neighbouring region, even when the addresses are contiguous (for example, `0x3FFFFFFC` in the default map).

When a condition fails, or when `has_zicclsm` is false, the access raises a misaligned address exception. The instruction is cancelled before it reaches the memory, which happens in the MEM stage when the Core has Zicsr and in the EX stage when it does not. With Zicsr enabled, the exception uses `mcause = 4` for a load and `mcause = 6` for a store, and `mtval` receives the effective address. Without Zicsr, the exception is only signalled on the Core outputs, as described in [02-barramento-e-memoria.md](../../contracts/02-barramento-e-memoria.md). The combination without Zicsr and without Zicclsm is a valid configuration.

## 3. Access That Crosses the Word

An access that crosses the word runs in two steps, both in the MEM stage.

| Step | Address presented | Store data and mask | Pipeline |
| :--- | :--- | :--- | :--- |
| 1 | Word of the first byte | Bytes that fit in that word | Stalled until the step completes |
| 2 | Next word, $\text{word} + 4$ | Remaining bytes | Advances normally |

A flip-flop holds the current step. It becomes `1` when step 1 completes and returns to `0` when the instruction leaves the MEM stage.

Step 1 completes when two conditions hold in the same cycle.

- The slave is ready. The internal RAM always is, since it answers in one cycle. The external regions (the SDRAM and, in the map with external FLASH, also the FLASH) are ready only when the ready signal arrives.
- The memory may advance, that is, the pipeline is not stalled by a multiplication or division or by waiting on an external region.

During step 1 the stall signal of the unit freezes the earlier stages and keeps the instruction in MEM. In step 2 that signal drops, and the instruction leaves MEM when the pipeline advances, like an aligned access. In the internal RAM step 1 completes in the first cycle, so the instruction occupies the MEM stage for two cycles instead of one.

## 4. Store That Crosses the Word

The store reaches MEM already positioned by the store manager. `SW` carries the whole register, and `SH` at offset 3 carries the halfword in `[31:16]`. The unit normalises the data to the low bytes, shifts it by $8o$ bits and the mask by $o$ bits, in a 64-bit and 8-bit pair. Step 1 writes the low half and step 2 writes the high half.

$$
\text{data}_{64} = \text{data} \ll 8o \qquad \text{mask}_8 = \text{mask} \ll o
$$

| Instruction | $o$ | Step 1 (bytes written) | Step 2 (bytes written) |
| :--- | :--- | :--- | :--- |
| `SW` | 1 | bytes 1, 2 and 3 (mask `1110`) | byte 0 (mask `0001`) |
| `SW` | 2 | bytes 2 and 3 (mask `1100`) | bytes 0 and 1 (mask `0011`) |
| `SW` | 3 | byte 3 (mask `1000`) | bytes 0, 1 and 2 (mask `0111`) |
| `SH` | 3 | byte 3 (mask `1000`) | byte 0 (mask `0001`) |

In loads the mask is zero, so no write happens.

The access is not atomic. It is two independent memory accesses, and an external observer may see the first half already written before the second.

## 5. Load That Crosses the Word

The synchronous memory delivers the data one cycle after receiving the address. For this reason the two halves of a load arrive in different stages.

| Cycle | Instruction stage | What happens |
| :--- | :--- | :--- |
| 1 | MEM, step 1 | The word of the first byte is requested and the pipeline waits |
| 2 | MEM, step 2 | The next word is requested. The step 1 data arrives and is kept in a register |
| 3 | WB | The step 2 data arrives and is joined to the kept data |

The register captures the step 1 data only in the first cycle of step 2, even if step 2 is held by an EX stall, so that the first word is not lost. In the WB stage the two words form a 64-bit pair, with the newly arrived word in the high half. The pair is shifted right by $8o$ bits, and the low word of the result is the load data aligned to byte 0.

$$
\text{pair} = \text{word}_{2} \mathbin{\|} \text{word}_{1} \qquad \text{data} = (\text{pair} \gg 8o)[31:0]
$$

That word goes to the load extender with zero shift, which applies sign or zero extension according to the instruction (`LW`, `LH` or `LHU`).

For `LW` with $o = 1$, the result bytes come from word 1 (bytes 1, 2 and 3) and from word 2 (byte 0), from least to most significant.

## 6. Summary of the Pipeline Path

| Stage | Role in the misaligned access |
| :--- | :--- |
| EX | Computes the effective address and positions the store data. Without Zicsr, it also detects the access that the hardware does not run |
| MEM | With Zicsr, detects the access that the hardware does not run and cancels it before it touches the memory. Splits the access that crosses the word into two steps, chooses the address, data and mask of each step, and stalls the pipeline in step 1 |
| WB | Joins the two words of a load that crossed, aligns the result and extends it |

An access that crosses the word costs one extra cycle in the internal RAM. In the external regions the cost grows with the wait of each step, since each depends on the ready signal of the slave.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
