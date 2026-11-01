# Memory Whose Width Differs from the CPU Word

The Core talks to the data memory in 32-bit words, accompanied by a 4-bit mask with one bit per byte. When the memory device has another width, an adapter between the two reconciles the difference. This document describes the rules the adapter must follow and the ways to build it.

## 1. What the CPU Expects

| Property | Value |
| :--- | :--- |
| Data | 32 bits, with the bytes in the positions of the address (little-endian) |
| Write mask | 4 bits, one per byte, `0` in loads |
| Address | Byte address, with the two low bits giving the position inside the word |
| Read | Whole 32-bit word, without a mask. The byte or halfword selection and the sign extension happen in the WB stage |

The adapter never receives the width of the instruction. It only sees the byte mask on a write and a whole word on a read.

The two data paths of the Core have different timing contracts, and that decides where the memory can sit.

| Path | Range | Wait |
| :--- | :--- | :--- |
| Internal RAM | `0x00008000` to `0x3FFFFFFF` | None. The answer always arrives one cycle after the address |
| External bus | `0x40000000` onwards | By the ready signal, of variable length |

In the map with external FLASH, chosen by the `ext_flash` parameter, there is no internal RAM, and the FLASH at `0x20000000` also answers through the external bus.

## 2. Relation Between the Widths

Let $W$ be the width of the device in bits. Two quantities describe the adaptation.

| Case | Condition | Quantity | Expression |
| :--- | :--- | :--- | :--- |
| Narrow | $W < 32$ | Slices per word | $n = 32 / W$ |
| Wide | $W > 32$ | CPU words per memory word | $m = W / 32$ |

In a narrow memory, one CPU word occupies $n$ positions of the device. In a wide memory, one device word holds $m$ CPU words, and the address chooses which one.

## 3. Memory Narrower than the CPU

There are two ways to build a 32-bit word out of narrow devices.

| Form | How it works | Cycles per access | Where it can sit |
| :--- | :--- | :--- | :--- |
| Devices in parallel | $n$ devices side by side, each with its slice of the data and of the mask, same address | The same as a 32-bit device | Internal RAM or external bus |
| One device, in series | A single device receives the $n$ slices in sequence | $n$ or more | External bus only |

The serial form needs waiting, and the internal RAM has no ready signal. A single narrow device, such as the SDRAM chip, therefore belongs to the external bus window.

### 3.1. Address

The adapter discards the two low bits of the byte address and works with the word index. That index, multiplied by $n$, gives the position of the first slice in the device.

### 3.2. Write

Each slice receives its part of the data and its part of the mask. For slice $k$, with $k = 0$ the least significant, the bits of the data and of the mask are the following.

$$
\text{data}_k = \text{data}[W(k+1)-1 : Wk] \qquad \text{mask}_k = \text{mask}\left[\tfrac{W}{8}(k+1)-1 : \tfrac{W}{8}k\right]
$$

A slice whose mask is all zero does not need to be written. Devices whose mask is active low, such as the SDRAM chip, receive the inverted mask.

Example with $W = 16$ and $n = 2$, for an `SH` at offset 2 of a word, with mask `1100`.

| Slice | Data bits | Slice mask | Mask at the chip (active low) | Effect |
| :--- | :--- | :--- | :--- | :--- |
| 0 | `[15:0]` | `00` | `11` | Nothing is written |
| 1 | `[31:16]` | `11` | `00` | Both bytes are written |

### 3.3. Read

The $n$ slices are read in sequence and concatenated, with slice 0 in the low bits. The word is valid only when the last slice arrives.

$$
\text{word} = \text{slice}_{n-1} \mathbin{\|} \dots \mathbin{\|} \text{slice}_1 \mathbin{\|} \text{slice}_0
$$

The whole word returns to the CPU even when the load asks for a byte, because the byte selection happens in the WB stage.

### 3.4. Ready signal

While the slices are not finished, the adapter keeps the ready signal at zero, and the CPU holds the MEM stage. The rules of the external bus apply to the adapter.

1. The address, the data, the mask and the read and write requests stay stable until ready rises.
2. The ready signal is a level. It stays at `1` until the adapter observes that the pipeline advanced.
3. The read data does not change while the load instruction is still in the WB stage. The adapter only changes the read data on the edge in which the pipeline advances.

## 4. Memory Wider than the CPU

With $m$ CPU words in each device word, the adapter uses the address bits just above the two low bits to choose the 32-bit lane.

$$
\text{lane} = \text{address}\left[\log_2 m + 1 : 2\right]
$$

### 4.1. Read

The device delivers the wide word, and the adapter returns only the chosen lane, without shifting it. The byte shift remains the job of the WB stage.

### 4.2. Write

The adapter places the 32-bit data in the chosen lane and builds a $W/8$-bit mask with only the 4 bits of that lane copied from the CPU mask. The other bytes stay disabled and are not changed.

| Device | CPU mask | Lane | Mask at the device |
| :--- | :--- | :--- | :--- |
| 64 bits ($m = 2$) | `0011` | 0 | `0000 0011` |
| 64 bits ($m = 2$) | `0011` | 1 | `0011 0000` |
| 128 bits ($m = 4$) | `1111` | 2 | `0000 1111 0000 0000` |

If the device has no byte mask, a partial write requires read, merge and write. The adapter reads the wide word, replaces the enabled bytes and writes the whole word. That access takes several cycles and can only sit on the external bus, for the same reason as section 3.

### 4.3. Using the width

A wide word allows several CPU words to be transferred at once. The data cache uses that, with 16-byte lines (four words) moved by a single request to the SDRAM controller. The line request carries words 1 to 3 on extra 32-bit ports, next to the one-word port. With $W = 128$, a line fits in a single device word.

## 5. Interaction with Misaligned Access

An access that crosses the word reaches the adapter as two independent accesses, each with the address of an aligned CPU word. The misaligned access unit of the Core presents the address of the next word in the second step, and the adapter treats each step as an ordinary access.

That rule has two consequences.

- The adapter cannot assume that the two words are in the same device word. In a wide memory they may be, but at a boundary between wide words they are in different ones.
- The first address of the instruction arrives with the two low bits filled in, and the adapter discards them.

## 6. Summary of the Decisions

| Question | Answer |
| :--- | :--- |
| The memory has $W < 32$ and a single device | Serialise in $n$ slices, use the external bus and the ready signal |
| The memory has $W < 32$ and $n$ devices | Place them in parallel, with no cycle cost, with the slice of the mask in each one |
| The memory has $W > 32$ | Select the lane by the address and replicate the data on a write |
| The memory has no byte mask | Read, merge and write, on the external bus |
| The device needs more than one cycle | External bus, never the internal RAM |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../LICENSE).
