# Arithmetic Logic Unit (ALU)

## 1. Overview

The ALU runs, combinationally in the EX stage, every integer operation of the RV32I base, the target address calculation of `JALR`, the immediate load of `LUI` and the evaluation of the six conditional branches. The data result leaves on `o_d` and the branch condition on `o_branch`.

One rule shapes the organization: the operation code is already the hardware decision. It has the same structure as the `funct3` field of the instructions, so the ALU picks the result straight from the bits of the code with no re-encoding, and the decoder of the ID stage delivers the code ready. A single adder-subtractor serves every operation that depends on a sum or a magnitude comparison.

## 2. Operation code

The `alu_op_t` code has 5 bits split into three fields.

| Bits | Name | Meaning |
| :--- | :--- | :--- |
| 4 | Control class | `1` for `JALR`, `LUI` and the six branches |
| 3 | Inversion | `1` inverts operand B and adds 1 (subtraction and comparisons); in right shifts, `1` selects the arithmetic shift |
| 2 to 0 | Result select | The `funct3` of R-type and I-type instructions; in branches, the `funct3` of the branch |

Outside the control class, the result select follows the RISC-V `funct3`.

| Bits 2 to 0 | Result on `o_d` |
| :--- | :--- |
| `000` | Sum or subtraction |
| `001` | Left shift |
| `010` | Signed less-than |
| `011` | Unsigned less-than |
| `100` | Exclusive OR |
| `101` | Right shift |
| `110` | OR |
| `111` | AND |

## 3. Operations

| Constant | Code | `o_d` | `o_branch` |
| :--- | :--- | :--- | :--- |
| `ALU_ADD` | `00000` | `a + b` | `0` |
| `ALU_SLL` | `00001` | `a << b[4:0]` | `0` |
| `ALU_XOR` | `00100` | `a xor b` | `0` |
| `ALU_SRL` | `00101` | logical `a >> b[4:0]` | `0` |
| `ALU_OR` | `00110` | `a or b` | `0` |
| `ALU_AND` | `00111` | `a and b` | `0` |
| `ALU_SUB` | `01000` | `a - b` | `0` |
| `ALU_SLT` | `01010` | `1` if signed `a < b`, else `0` | `0` |
| `ALU_SLTU` | `01011` | `1` if unsigned `a < b`, else `0` | `0` |
| `ALU_SRA` | `01101` | arithmetic `a >> b[4:0]` | `0` |
| `ALU_JALR` | `10000` | `(a + b)` with bit 0 cleared | `0` |
| `ALU_LUI` | `10001` | `b` | `0` |
| `ALU_BEQ` | `11000` | `0` | `a = b` |
| `ALU_BNE` | `11001` | `0` | `a /= b` |
| `ALU_BLT` | `11100` | `0` | signed `a < b` |
| `ALU_BGE` | `11101` | `0` | signed `a >= b` |
| `ALU_BLTU` | `11110` | `0` | unsigned `a < b` |
| `ALU_BGEU` | `11111` | `0` | unsigned `a >= b` |

## 4. Shared adder-subtractor

With $inv$ equal to bit 3 of the code, the adder computes

$$S = a_{\mathrm{eff}} + (b \oplus inv) + inv,$$

in 33 bits, so that the extra bit is the carry out $c_{out}$. With $inv = 0$ the result is $a + b$, and with $inv = 1$ it is $a - b$ in two's complement. The same $S$ serves `ADD`, `SUB`, `JALR`, `LUI`, `SLT`, `SLTU` and the four magnitude comparisons of the branches.

The comparisons come out of the subtraction with no other comparator:

$$a <_u b = \lnot c_{out}$$

$$a <_s b = \begin{cases} a_{31} & \text{if } a_{31} \neq b_{31} \\ S_{31} & \text{otherwise} \end{cases}$$

When the signs differ, the negative operand is the smaller one. When they match, the subtraction cannot overflow and its sign decides.

The equality of `BEQ` and `BNE` uses a dedicated comparator between $a$ and $b$, which does not wait for the carry chain of the adder.

## 5. Branches

In the six branches, the class bit and the inversion bit are `1`, and the select field is the `funct3` of the branch. The ALU zeroes `o_d` and evaluates `o_branch` as follows.

| Branch `funct3` | Branch | `o_branch` |
| :--- | :--- | :--- |
| `000` | `BEQ` | equality |
| `001` | `BNE` | negation of equality |
| `100` | `BLT` | signed less-than |
| `101` | `BGE` | negation of signed less-than |
| `110` | `BLTU` | unsigned less-than |
| `111` | `BGEU` | negation of unsigned less-than |

The branch target address is computed by dedicated adders in the EX stage, and `o_branch` only decides whether it is taken.

## 6. Shifters

There is one left shifter and one right shifter. The right one takes a fill bit on the left, which is the sign of $a$ when the inversion bit is `1` (`SRA`) and zero when it is `0` (`SRL`). The shift amount is the low 5 bits of $b$.

Each shifter is a cascade of 4-to-1 multiplexers, one per pair of amount bits: the first shifts by 0 to 3 positions, the second by 0, 4, 8 or 12, and the third by 0 or 16. A 4-to-1 multiplexer fits in a 6-input LUT, so the whole shift takes three logic levels.

## 7. Result selection

The data result leaves an OR of eight terms, each enabled by one bit of the one-hot select `i_res_sel`: sum, left shift, signed less-than, unsigned less-than, XOR, right shift, OR and AND. The ID stage decodes the operation code into that select, which travels through the ID/EX register, so the ALU decodes nothing. JALR and LUI select the sum, and the branches select no term, which zeroes the data result.

The terms split into two groups. The fast group holds XOR, OR, AND and the less-than bits, which depend only on bitwise logic and the comparators. The slow group holds the sum and the two shifts. The two groups meet in a last OR.

## 8. `LUI` and `JALR`

`LUI` belongs to the control class with the inversion at `0` and bit 0 at `1`. The ALU forces operand A to zero and adds, so the result is the immediate of operand B itself, with no extra source in the result multiplexer.

`JALR` belongs to the control class with the inversion at `0` and bit 0 at `0`. The result is the sum with bit 0 cleared, as the address of an indirect jump requires.

In both operations the result select field is ignored and the sum is always the result.

## 9. Verification

| Test | What it checks |
| :--- | :--- |
| `ALU` | Each operation alone (with the one-hot select the ID stage would produce) and, for all 18, a reference model on edge values (`0`, `1`, `31`, `32`, `0x7FFFFFFF`, `0x80000000`, `0xFFFFFFFF`) and 300 random pairs |
| `control_unit` | The code the decoder generates for each instruction, against the control signal table |
| Core tests | Programs of instructions, traps, stalls and `fence.i` that exercise the ALU in the pipeline |
