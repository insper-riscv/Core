# Misaligned Memory Access (Zicclsm)

The Zicclsm extension requires loads and stores with a misaligned address to work in hardware instead of raising an exception. This document describes how the Core executes those accesses and the path a misaligned instruction takes through the pipeline. The `has_zicclsm` parameter turns the extension on and off.

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

The extension covers only the main memory. The address ranges come from the Core memory map, which has two forms, chosen by the `ext_flash` parameter.

In the default map the main memory is the internal RAM and the SDRAM window.

| Region | Range | Misaligned access in hardware |
| :--- | :--- | :--- |
| BOOT_ROM and internal FLASH | below `0x00008000` | No, raises an exception |
| Internal RAM | `0x00008000` to `0x3FFFFFFF` | Yes |
| SDRAM | `0x40000000` to `0x7FFFFFFF` | Yes |
| Peripherals | `0x80000000` onwards | No, raises an exception |

In the map with external FLASH there is no internal RAM, and the main memory is the FLASH, which sits behind the caches, and the SDRAM window.

| Region | Range | Misaligned access in hardware |
| :--- | :--- | :--- |
| BOOT_ROM and unmapped range | below `0x20000000` | No, raises an exception |
| External FLASH | `0x20000000` to `0x3FFFFFFF` | Yes |
| SDRAM | `0x40000000` to `0x7FFFFFFF` | Yes |
| Peripherals | `0x80000000` onwards | No, raises an exception |

The decision is taken in the EX stage, before the instruction reaches the memory. An access that crosses the word is executed only when it meets the three conditions below.

1. The address is in the main memory of the map in use.
2. Both words are in the same region. The last word of each region is rejected, because the next word belongs to the neighbouring region.
3. The next word exists, that is, the address is not the last word of the 32-bit space.

When a condition fails, or when `has_zicclsm` is false, the instruction is cancelled in EX before it reaches the MEM stage. With Zicsr enabled, the exception uses `mcause = 4` for a load and `mcause = 6` for a store, and `mtval` receives the effective address. Without Zicsr, the exception is only signalled on the Core outputs. The Core refuses to elaborate with `has_zicclsm` false and without Zicsr, because nothing would handle the access.

## 3. Access That Crosses the Word

An access that crosses the word runs in two steps, both in the MEM stage.

| Step | Address presented | Store data and mask | Pipeline |
| :--- | :--- | :--- | :--- |
| 1 | Word of the first byte | Bytes that fit in that word | Stalled until the step completes |
| 2 | Next word, $\text{word} + 4$ | Remaining bytes | Advances normally |

A flip-flop indicates the current step. It becomes `1` when step 1 completes and returns to `0` when the instruction leaves the MEM stage.

Step 1 completes when two conditions hold in the same cycle.

- The slave is ready. The internal RAM always is, because it answers in one cycle. The SDRAM, and the external FLASH in the map with external FLASH, are ready only when the ready signal arrives.
- The memory can advance, that is, the pipeline is not stalled by a multiplication or division nor by an SDRAM wait.

During step 1 the stall signal of the unit freezes the earlier stages and holds the instruction in MEM. In step 2 that signal drops, and the instruction leaves MEM when the pipeline advances, like an aligned access.

## 4. Store That Crosses the Word

The store reaches MEM already positioned by the store manager. `SW` carries the whole register, and `SH` at offset 3 carries the halfword in `[31:16]`. The unit normalises the data to the low bytes, shifts it by $8o$ bits and the mask by $o$ bits, into a 64-bit and 8-bit pair. Step 1 writes the low half and step 2 writes the high half.

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

The access is not atomic. The first half may already be written when the second fails or is interrupted.

## 5. Load That Crosses the Word

The synchronous memory delivers the data one cycle after receiving the address. The two halves of a load therefore arrive in different stages.

| Cycle | Stage of the instruction | What happens |
| :--- | :--- | :--- |
| 1 | MEM, step 1 | The word of the first byte is requested and the pipeline waits |
| 2 | MEM, step 2 | The next word is requested. The data of step 1 arrives and is kept in a register |
| 3 | WB | The data of step 2 arrives and is joined to the kept data |

In the WB stage the two words form a 64-bit pair, with the newly arrived word in the high half. The pair is shifted right by $8o$ bits, and the low word of the result is the load data aligned to byte 0.

$$
\text{pair} = \text{word}_{2} \mathbin{\|} \text{word}_{1} \qquad \text{data} = (\text{pair} \gg 8o)[31:0]
$$

That word goes to the load extender with offset zero, which applies the sign or zero extension according to the instruction (`LW`, `LH` or `LHU`).

For `LW` with $o = 1$, the bytes of the result come from word 1 (bytes 1, 2 and 3) and from word 2 (byte 0), from least to most significant.

## 6. Summary of the Pipeline Path

| Stage | Role in the misaligned access |
| :--- | :--- |
| EX | Detects the misalignment, decides between executing in hardware and raising an exception, and positions the store data |
| MEM | Splits the access that crosses the word into two steps, chooses the address, data and mask of each step, and stalls the pipeline in step 1 |
| WB | Joins the two words of a load that crossed, aligns the result and extends it |

An access that crosses the word costs one extra cycle in the internal RAM. In the SDRAM and in the external FLASH the cost grows with the wait of each step, because each one depends on the ready signal of the slave.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../LICENSE).
