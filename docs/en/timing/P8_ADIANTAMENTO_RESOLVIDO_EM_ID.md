# Step F.P8: forwarding selection resolved in ID and replicated

🌐 [Português](../../pt-br/timing/P8_ADIANTAMENTO_RESOLVIDO_EM_ID.md) · [English](P8_ADIANTAMENTO_RESOLVIDO_EM_ID.md)

## 1. Summary

| | |
| :--- | :--- |
| Problem | The EX stage chose the source of each operand from six registered bits (three matches and three valid bits), and the result, with a fan-out of 132, drove the operand multiplexer. The selection and the network added about 2.9 ns to the start of the EX loop |
| Change | The ID stage computes the resolved selector (`forwarding_match` with the valid bits, then `forwarding_unit` with the priority), and `ID/EX` registers it in `FWD_COPIES` copies per operand. Each copy drives one slice of the operand multiplexer in EX |
| Effect on behavior | None. The registered selector is the one EX used to compute |
| Effect on cycles per instruction | None |

## 2. Validity of the instructions ahead

The instruction in ID enters EX on the next edge, and the three ahead of it move to EX/MEM, MEM/WB and WB2. The match of each one only counts if it is still valid after that edge, and `core` hands `stage_id` the enables already conditioned.

| Instruction ahead | Writes a register and stays valid after the edge when |
| :--- | :--- |
| ID/EX (moves to EX/MEM) | $\text{we\_reg} \wedge \text{valid} \wedge \neg\,\text{trap\_sig}$ |
| EX/MEM (moves to MEM/WB) | $\text{we\_reg} \wedge \text{valid}$ |
| MEM/WB (moves to WB2) | `wb_we` |

The discard of an instruction ahead by `trap_take` or by a MEM exception is not in the conditions, because the same event clears `ID/EX` (`flush_id_ex`) and the registered selector goes back to "00". Only `trap_sig`, the no-effect exception signal of the core without Zicsr, discards the EX instruction without clearing `ID/EX`. The late signals of the EX loop therefore do not reach the selector input, and the registered selector equals the one EX computed from the already registered valid bits.

## 3. Verification

| Guarantee | Verification |
| :--- | :--- |
| The match keeps destination `x0` out and respects the valid bits | Entity test `ForwardingMatch` and `stage_id` test |
| The priority between sources is EX/MEM, MEM/WB, WB2 | Entity test `ForwardingUnit`, exhaustive |
| Each copy drives its slice of the operand | `stage_ex` test with different selectors per copy |
| The core behaves the same | Every core test (`cores/`), with the same cycle count and the same final RAM content as before the change |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
