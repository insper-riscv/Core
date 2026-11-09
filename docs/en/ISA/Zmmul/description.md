# Zmmul: Implementation in the Core

This document describes how the Core executes the `Zmmul` instructions. What the manual requires is in [instructions.md](instructions.md). The decoder, the execution unit, the pipeline stall and the pair fusion are shared with `M` and are in [M](../M/description.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 11, M Extension, section 11.1.3 (Zmmul, version 1.0) |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |

## 2. Configuration

| Constant | Default | Effect |
| :--- | :--- | :--- |
| `HAS_ZMMUL` | `false` | Instantiates the decoder and the multiplier, without the divider (4 instructions) |

The divider is instantiated only with `HAS_M`, so `HAS_ZMMUL = true` with `HAS_M = false` gives the profile without division. Valid profiles never combine the two extensions (see the [README](../../../../README.en.md)).

## 3. Decoding without Division

The division parameter of the decoder receives the value of `HAS_M`. Without division, only the `funct3` values with bit 2 at zero are claimed, that is, the four multiplications. An instruction with `funct7 = 0000001` and a division `funct3` is not claimed, and the control unit marks it illegal. The rest of the decoding is in [M](../M/description.md).

## 4. Radix-2 Booth Multiplier

The multiplier performs the signed 32 by 32-bit multiplication and produces the 64-bit product. It keeps a 33-bit accumulator, the 32-bit multiplier, an auxiliary bit on the right and the multiplicand sign-extended to 33 bits. At each step it examines the pair formed by the least significant bit of the multiplier and the auxiliary bit.

| Pair | Operation on the accumulator |
| :--- | :--- |
| `01` | Adds the multiplicand |
| `10` | Subtracts the multiplicand |
| `00` or `11` | Keeps the accumulator |

The whole is then shifted one bit to the right, arithmetically. After 32 steps, the accumulator and the multiplier form the high and low halves of the product. The latency is 33 cycles (1 of initialization and 32 steps), and the signed range includes $-2^{31}$.

The low half holds for any sign interpretation. The high half comes out interpreted as signed in both operands, and `multdiv` corrects it for the unsigned modes with two 32-bit adders.

$$
\text{high}_{\text{corrected}} = \text{high} + (A_{31} \land \neg s_A) \cdot B + (B_{31} \land \neg s_B) \cdot A \pmod{2^{32}}
$$

In this expression, $s_A$ and $s_B$ are 1 when the respective operand is signed. For `MULH` the correction is null, for `MULHSU` only the term that adds $A$ applies and for `MULHU` both terms apply.

## 5. Pipeline Stall

Multiplication has a latency of 33 cycles in the unit, and the pipeline stalls for 35, because the stall also covers the final state and the cycle in which the result is captured. The stall logic and the cost of the other operations are in [M](../M/description.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
