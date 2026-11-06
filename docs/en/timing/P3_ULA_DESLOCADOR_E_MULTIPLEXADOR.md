# Step F.P3: ALU shifter and result multiplexer

## 1. Summary

| | |
| :--- | :--- |
| Problem | The right shifter and the ALU result multiplexer added up to 4.5 ns and six logic levels |
| Change | The shifters (left, and right with a selectable sign fill) are stages of 4-to-1 multiplexers, one per two bits of the amount, and the result comes out of an AND-OR with a one-hot selection decoded in ID |
| Shifter levels | Three: the stages cover bits 1:0, 3:2 and 4 of the amount |
| Adder | A single one, shared by add, subtract, comparisons, JALR, LUI and branches |
| Effect on behavior | None |

## 2. Structure

| Block | How it is built |
| :--- | :--- |
| Adder-subtractor | The inversion bit of the operation enters B with carry-in 1; the sign and the carry-out of the difference give less-than with and without sign |
| Equality | Dedicated comparator, which does not wait for the carry chain |
| Shifters | $\lceil 5/2 \rceil = 3$ stages of 4-to-1 multiplexers (one 6-input LUT each) |
| Fast result group | XOR, OR, AND and the SLT and SLTU bits, which do not wait for the adder nor the shifters |
| Slow result group | Sum and shifts |

## 3. Equivalence with the reference ALU

The `alu_props.sv` formal proof compares the ALU output with the operators of the language (add, difference, signed and unsigned comparisons, three shifts by the low five bits of B, bitwise logic, LUI, JALR and the six branch conditions), for all 18 operations and all pairs of operands, with the one-hot selection that the decoder produces for each operation.

| Proof | Wanted result |
| :--- | :--- |
| Equivalence of the data and of the branch condition | Passes |
| Cover: arithmetic shift, sign-crossing comparisons, JALR and branches | Reachable |
| Ten mutants (sign fill, SLT bit, JALR bit 0, shifter digits, equality, LUI, subtract carry, XOR selection, BGEU condition) | All caught |

The `ALU` entity test keeps covering the 18 operations with random values.

## 4. Measurement

The RTL of this step is the one measured in `P1_EXCECAO_DE_ACESSO_EM_MEM.md`, section 4. The paths through the ALU (from `ID/EX` and the forwarding to `EX/MEM`) are not among the worst of the core report, which are the CSR read feeding the CSR write and the instruction cache loop.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
