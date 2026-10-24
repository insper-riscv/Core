# Unsigned Divider Error with Divisors Above 2^31

## 1. Summary

The RV32M divider stored the partial remainder in 33 signed bits and, at each step, discarded the highest bit before shifting. With an unsigned divisor greater than $2^{31}$, the partial remainder reaches $\pm 2^{31}$ or more in magnitude, the discarded bit ceases to be a pure sign extension, and the next step adds or subtracts the divisor on the wrong side. Both the quotient and the remainder come out wrong.

| | |
| :--- | :--- |
| Symptom | `divu` and `remu` return wrong quotient and remainder when the divisor is greater than $2^{31}$ |
| Condition | Unsigned operation with divisor $> 2^{31}$, for most dividends |
| Fix | Internal partial remainder and divisor widened to 34 bits |
| Test | Entity test of the divider against the ISA-defined result, with boundary value pairs and random pairs |
| Discovered by | ACT4 tests `M-divu-00` and `M-remu-00` |

`DIV` and `REM` are unaffected because the divisor enters in absolute value, at most $2^{31}$, and the partial remainder never exceeds $2^{31}$.

## 2. How the Divider Computes

Non-restoring division repeats 32 times over the pair (partial remainder $A$, quotient $Q$) and the positive divisor $M$:

1. Shifts the pair $\{A, Q\}$ one position to the left; the highest bit of $Q$ becomes the least significant bit of $A$.
2. If $A \ge 0$, subtracts $M$; otherwise, adds $M$.
3. The least significant bit of $Q$ receives 1 if the new $A \ge 0$, else 0.

At the end, if $A < 0$, it adds $M$ one last time to obtain the remainder. The sign of $A$ decides the operation at every step, so $A$ must represent the remainder without sign ambiguity.

## 3. Value Range of the Partial Remainder

Between steps, the partial remainder satisfies $-M \le A < M$. Therefore, after shifting:

$$
-2M \le A_{\text{shifted}} = 2A + b < 2M, \qquad b \in \{0, 1\}
$$

With $M < 2^{32}$ (32-bit unsigned divisor), the shifted value reaches nearly $2^{33}$ in magnitude. Representing $[-2^{33}, 2^{33})$ in two's complement requires 34 bits.

| Width of $A$ | Representable $A_{\text{shifted}}$ range | Maximum correct divisor |
| :--- | :--- | :--- |
| 33 bits | $[-2^{32}, 2^{32})$ | $2^{31}$ |
| 34 bits | $[-2^{33}, 2^{33})$ | $2^{32} - 1$ |

The shift appended the bit from $Q$ to the lower 32 bits of $A$, discarding bit 32. That is equivalent to sign-extending only while $-2^{31} \le A < 2^{31}$, which holds for any divisor up to $2^{31}$. Above that, $A$ leaves this range in the very first steps, because a small dividend leaves the partial remainder negative near $-M$. The discarded bit carried information, and the shifted value changes sign or magnitude.

## 4. Example

`divu` with dividend 1 and divisor $\texttt{0x80000001}$. The correct result is quotient 0 and remainder 1.

| Width of $A$ | Quotient | Remainder |
| :--- | :--- | :--- |
| 33 bits | $\texttt{0x7FFFFFFE}$ | 3 |
| 34 bits | 0 | 1 |

With this dividend, $A$ becomes negative right on the first step, near $-M \approx -2^{31}$. From then on, the 33-bit shift loses bit 32 of $A$ and each subsequent step starts from a wrong value.

## 5. The Fix

| Element | Width |
| :--- | :--- |
| Partial remainder $A$ and step variables | 34 signed bits |
| Divisor $M$ | 34 signed bits, zero-extended in the two highest bits |
| Shift | $A_{\text{shifted}} = A[32{:}0] \,\&\, Q[31]$ |

The outputs remain 32 bits wide because the final remainder fits in 32 bits ($0 \le A < M < 2^{32}$ at the end of the correction step).

## 6. How the Test Proves the Fix

The `non_restoring_divider` entity test runs the divider in isolation and compares quotient and remainder against the ISA-defined result computed in Python.

| Test | Inputs |
| :--- | :--- |
| Unsigned boundaries | All pairs from $\{0, 1, 2, 3, \texttt{0x7FFFFFFF}, \texttt{0x80000000}, \texttt{0x80000001}, \texttt{0xFFFFFFFE}, \texttt{0xFFFFFFFF}\}$ |
| Signed boundaries | The same pairs, including $-2^{31} / -1$ and division by zero |
| Random | 60 32-bit pairs in both modes, with a fixed seed |

The unsigned boundary test exercises 23 pairs that the 33-bit divider computes wrong, all with divisor $\ge \texttt{0x80000001}$; with 34 bits none fail. All three tests pass. The project simulation suite (89 programs) and the 47 ACT4 runs for the I and M extensions pass with the fixed divider.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
