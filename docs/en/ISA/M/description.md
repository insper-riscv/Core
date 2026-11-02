# M Extension: Implementation in the Core

This document describes how the Core executes the `M` instructions. What the manual requires (encoding and semantics) is in [instructions.md](instructions.md). Multiplication is shared with `Zmmul`, and the Booth multiplier is described in [Zmmul](../Zmmul/description.md).

## 1. Configuration

The `has_m` generic of `core` chooses what is instantiated.

| Generic | Default | Effect |
| :--- | :--- | :--- |
| `has_m` | `false` | Instantiates the decoder, the multiplier and the divider (8 instructions) |

The decoder and the execution unit are generated when `has_m` or `has_zmmul` is `true`, and the divider only when `has_m` is `true`. So `has_m` already includes multiplication, and the profile without division uses only the `has_zmmul` generic, described in [Zmmul](../Zmmul/description.md). Valid profiles never combine the two extensions (see the [README](../../../../README.en.md)).

## 2. Structure

| Stage | Entity | Function |
| :--- | :--- | :--- |
| ID | `m_decode` | Recognizes the extension instruction and drives the controls |
| EX | `multdiv` | Coordinates the operation, selects the result and raises the pipeline stall |
| EX | `booth_multiplier_rv32` | 64-bit product (multiplication instructions) |
| EX | `non_restoring_divider_rv32` | 32-bit quotient and remainder (division instructions) |
| EX | `muldiv_fusion` | Keeps the last operation for pair fusion |

## 3. Decoding in the ID Stage

The decoder claims the instruction when the `opcode` is the register-register one, `funct7` is `0000001` and `funct3` belongs to the implemented operations. On claiming it, it drives three controls.

| Control | Value | Effect |
| :--- | :--- | :--- |
| Selection of the multiply and divide unit result | `1` | The EX stage uses the unit result instead of the ALU |
| Write to `rd` | `1` | The result is written to the register file |
| Operand A | `rs1` | The first operand comes from `rs1` |

The decoder division parameter takes the value of `has_m`. Without division (`Zmmul` profile), only the `funct3` values with bit 2 at zero are claimed, that is, the four multiplications.

### 3.1. Disabled Instructions

When an instruction with `funct7 = 0000001` is not claimed, either because neither extension is enabled or because the `funct3` is a division in the `Zmmul` profile, the control unit flags it as illegal. The ID stage only cancels that flag for instructions the decoder claimed. Without both extensions, the EX stage does not instantiate the unit, and its stall and result are tied to zero.

## 4. Execution in the EX Stage

`multdiv` generates a start pulse in the first cycle in which a valid extension instruction enters the EX stage, keeps the `funct3` from that pulse on and drives the multiplier (bit 2 of `funct3` at zero) or the divider (bit 2 at one). The operands are the values of `rs1` and `rs2` with data forwarding already applied.

The sign code derived from the kept `funct3` says which operands are signed.

| Instructions | Operand A | Operand B |
| :--- | :--- | :--- |
| `MUL`, `MULH`, `DIV`, `REM` | Signed | Signed |
| `MULHSU` | Signed | Unsigned |
| `MULHU`, `DIVU`, `REMU` | Unsigned | Unsigned |

Multiplication uses the radix-2 Booth multiplier described in [Zmmul](../Zmmul/description.md), which produces the 64-bit product and delivers the low and high halves.

### 4.1. Non-Restoring Divider

The divider works on the magnitude of the operands in signed divisions and on the values themselves in unsigned ones. The partial remainder and the divisor have 34 bits, which accommodates unsigned divisors above $2^{31}$ (see [DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md](../../bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md)). The states of the normal case are those in the table.

| State | Cycles | Operation |
| :--- | :--- | :--- |
| Start | 1 | Computes the magnitude of the operands and loads the registers |
| Compute | 32 | Shifts the partial remainder; subtracts the divisor if the remainder is nonnegative, adds it if negative; records one quotient bit |
| Correction | 1 | Adds the divisor to the remainder if it ended negative |
| Sign adjustment | 1 | Applies the signs: the quotient is negated if the operand signs differ, and the remainder is negated if the dividend is negative |

In unsigned division the adjustment copies quotient and remainder unchanged. The latency is 35 cycles in the normal case, the sum of the cycles in the table.

The manual special cases are detected before the computation and skip the 32 iterations; the latency is 2 cycles.

| Condition | Quotient | Remainder |
| :--- | :--- | :--- |
| Divisor equal to zero (signed or unsigned) | `0xFFFFFFFF` | Dividend |
| Dividend $-2^{31}$ and divisor $-1$ (signed) | `0x80000000` | `0` |

### 4.2. Result

Each operator signals busy and done. The final result is selected by the kept `funct3`.

| Instruction | Source |
| :--- | :--- |
| `MUL` | Low half of the product |
| `MULH`, `MULHSU`, `MULHU` | High half of the product, with the correction described in [Zmmul](../Zmmul/description.md) |
| `DIV`, `DIVU` | Quotient |
| `REM`, `REMU` | Remainder |

The result is captured in a register in the completion cycle and delivered to the EX stage.

## 5. Pipeline Stall

`multdiv` keeps its stall output active from the start pulse cycle, throughout the computation and in the completion cycle. The pulse cycle is covered by a combinational term, so the instruction stalls already in the first cycle, and the rest comes from a flip-flop that keeps the busy of the previous cycle. Thus the completion pulse does not cross the pipeline stall logic.

The `core` combines this stall with the other conditions (see section 2.4 of [ARCHITECTURE.md](../../ARCHITECTURE.md)) and counts it in Zihpm event 1. The cost per instruction, in stall cycles, is in the table.

| Case | Latency of the unit | Stall cycles |
| :--- | :---: | :---: |
| Multiplication | 33 | 35 |
| Normal division | 35 | 37 |
| Division by zero or overflow | 2 | 4 |
| Fused operation (section 6) | Not applicable | 3 |

In every case the stall lasts the latency of the operator plus 2 cycles. The busy signal of the operator rises combinationally in the cycle of the start pulse and falls only after the final state, and the stall uses the registered busy signal, so it also covers the cycle in which the result is captured. Multiplication has a latency of 33 cycles (1 of load and 32 steps) and stalls for 35. Normal division has a latency of 35 cycles (1 of start, 32 iterations, 1 of correction and 1 of sign adjustment) and stalls for 37. In the special cases the latency is 2 cycles (start and detection) and the stall lasts 4.

The effect of the registered stall on the critical path is in [STALL_REGISTRADO_DO_MULTDIV.md](../../timing/STALL_REGISTRADO_DO_MULTDIV.md).

## 6. Pair Fusion

The manual recommends executing `MULH[[S]U]` followed by `MUL`, and `DIV[U]` followed by `REM[U]`, as a single operation. The `muldiv_fusion` entity fulfills the recommendation by keeping the last operation completed in full: the two operands, the `funct3` and the full result (the 64-bit product without the sign correction, or the quotient and remainder pair).

### 6.1. Hit Criterion

In the cycle after the start pulse, with the operands already latched in the EX stage, the three conditions below must hold at once, besides a valid record existing.

| Condition | Detail |
| :--- | :--- |
| Same values | Both operands have the same values as the recorded ones, regardless of the source and destination registers |
| Same family | Multiplication, `DIV` with `REM`, or `DIVU` with `REMU` |
| Other operation | The `funct3` differs from the recorded one |

Since the comparison is by value, a hit is always correct. The following do not fuse: repetition of the same operation, different values, different families, signed division followed by unsigned and a different operation in between, because the record keeps only the last one.

### 6.2. Sequence

On a hit, the running unit is interrupted and the result comes out of the record one cycle later.

| Cycle | Event |
| :--- | :--- |
| 0 | Start pulse |
| 1 | Comparison and hit |
| 2 | Completion, with the result taken from the record and the high-half correction applied to the mode of the second instruction |

The record is valid from the first completed operation on and only reset invalidates it. A fused operation does not change it. Each fused operation is counted in Zihpm event 9.

## 7. Formal Verification

The properties in `formal/muldiv_fusion_props.sv` verify `muldiv_fusion` by BMC and cover (see [FORMAL.md](../../FORMAL.md)). A model keeps the last completed operation, and the assertions require a hit only in the cycle after a start, with a valid record, same operand values, same family and another operation. They also require that, in the fused completion cycle, the record shows exactly the full result that the earlier execution on those operands delivered. The covers reach a multiplication hit and a division hit, and the cases of equal operands with a different family or with the same operation.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
