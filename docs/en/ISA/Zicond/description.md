# Zicond: Implementation in the Core

This document describes how the Core executes the `Zicond` instructions. What the manual requires is in [instructions.md](instructions.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 10, Zicond Extension for Integer Conditional Operations, version 1.0.0 |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |

## 2. Configuration

| Constant | Default | Effect |
| :--- | :--- | :--- |
| `HAS_ZICOND` | `false` | Instantiates the decoder in the ID stage and the execution unit in the EX stage |

With `HAS_ZICOND = false`, no decoder claims the two encodings, and the control unit marks them as illegal instructions, like any encoding outside RV32I. The `rv32im_zicond` profile turns the generic on for the GHDL build.

## 3. Decoding in the ID Stage

The decoder claims the instruction when the three fields in the table below match, whatever the values of `rd`, `rs1` and `rs2`.

| Field | Value |
| :--- | :--- |
| `opcode` | `0110011` |
| `funct7` | `0000111` |
| `funct3` | `101` or `111` |

For a claimed instruction, the decoder enables the write to `rd`, selects `rs1` as operand A and removes the illegal-instruction signal. It hands the EX stage a 5-bit operation code in the field that already carries the ALU operation, one code per instruction.

| Instruction | Operation code |
| :--- | :--- |
| `czero.eqz` | `01100` |
| `czero.nez` | `01110` |

Neither code is an ALU operation, so the EX stage tells the instructions apart without a new signal in the ID/EX register. The ALU result selection stays that of an addition, and that result is not used.

## 4. Execution in the EX Stage

The execution unit is combinational and receives $rs1$ and $rs2$ after forwarding, so it reads the value produced by an earlier instruction still in the pipeline. With $c$ equal to 1 when $rs2 = 0$, the result is given below.

$$
rd = \begin{cases}
0 & \text{if } (\texttt{czero.eqz} \land c) \lor (\texttt{czero.nez} \land \lnot c) \\
rs1 & \text{otherwise}
\end{cases}
$$

The result enters the EX stage result multiplexer, which picks it when the operation code is one of the two instructions. From there it follows the common path of an arithmetic instruction: forwarding to the following instructions and the write to `rd` in the WB stage. The instruction takes one cycle in the EX stage and does not stall the pipeline.

## 5. Verification

| Check | What it covers |
| :--- | :--- |
| Decoder entity test | The two encodings, the independence from the register fields and the neighboring encodings that are not claimed |
| Execution unit entity test | The truth table, each of the 32 bits of `rs1` and `rs2`, pseudorandom operands and the ALU operation codes that are not claimed |
| Core test with `HAS_ZICOND` | `rs2` zero and nonzero, `rd` equal to `rs1`, `rd` equal to `x0`, `rs1` equal to `x0`, `rs1` and `rs2` in the same register and forwarding of the operand and of the result |
| Core test without `HAS_ZICOND` | Both instructions raise the illegal-instruction exception (cause 2) |
| Formal proofs | The semantics of the table in section 2 of [instructions.md](instructions.md) and the exactness of the claimed encoding, each property with VHDL mutants that must be caught |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
