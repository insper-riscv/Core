# Taken Branch Wiped Out by Flush While the Pipeline Is Stalled

## 1. Summary

When the MEM stage waits on a variable-latency memory (SDRAM), the entire pipeline stalls. A taken branch sitting in EX at that moment was wiped out by the flush before reaching MEM, and the PC was not redirected. After the wait ended, the core continued sequentially and executed the wrong-path instructions.

| | |
| :--- | :--- |
| Symptom | A loop or jump right after an SDRAM load follows the wrong path whenever the wait is greater than zero cycles |
| Condition | Taken branch or jump in EX on the same cycle in which MEM is waiting on an SDRAM access |
| Fix | Flush takes effect only when the pipeline advances |
| Test | Core entity test with a variable-latency SDRAM, in which the branch skips three instructions |

## 2. How the Pipeline Handles a Taken Branch

Branches are resolved in EX. On the cycle in which a branch is resolved, on the same clock edge:

| Register | What happens on the clock edge |
| :--- | :--- |
| EX/MEM | Captures the branch result and carries it forward |
| ID/EX and IF/ID | Receive a flush, discarding the wrong-path instructions already fetched |
| PC | Receives the target address |

The ID/EX register holds the instruction currently in EX. Flushing it does not lose the branch because, on the same edge, EX/MEM has already captured it.

## 3. What Went Wrong When the Pipeline Was Stalled

When an SDRAM access is in MEM and has not yet completed, the pipeline stalls: the ID/EX, EX/MEM, and MEM/WB registers and the PC have their enable held at zero. If a taken branch is in EX at that time:

1. EX/MEM does not capture the branch, because it is stalled.
2. The PC is not updated, because it is stalled.
3. The flush did not depend on enable: in ID/EX and IF/ID, the flush condition was checked before the enable. Because the branch stayed in EX, the flush condition stayed true on every wait cycle.
4. ID/EX was emptied on the first wait cycle, and with it the branch itself.

When the memory access completed, the branch no longer existed in any stage, and the PC continued from where it was. For example, with the branch at address $A$ and the target at $A + 16$:

| Moment | PC (fetch) | ID | EX | What is lost |
| :--- | :--- | :--- | :--- | :--- |
| Before the wait | $A + 8$ | $A + 4$ | branch ($A$) | nothing |
| During the wait | $A + 8$ | empty | empty | the branch |
| After the wait | $A + 8$, $A + 12$, ... | sequential instructions | wrong path | redirection to $A + 16$ |

The error only appears if the target differs from the address the PC was already fetching. A branch that skips a single instruction lands at $A + 8$ and appears correct by coincidence.

## 4. When It Happens

Both conditions must hold at the same time:

- an SDRAM load or store in MEM, with memory not yet ready;
- a taken branch or jump in EX on the same cycle.

The most common pattern is a C loop: an SDRAM load followed by the branch back to the start of the loop. With a zero-cycle wait the bug does not occur, which is why it only appears with a multi-cycle memory.

## 5. The Fix

The flush now takes effect only when the pipeline advances, that is, when neither the muldiv unit nor SDRAM is stalling:

$$
\text{flush} = (\text{branch taken} \lor \text{jump taken}) \land \text{pipeline advances}
$$

While the pipeline is stalled, the branch stays in EX without being flushed. When the pipeline resumes, the branch is captured by EX/MEM and both the flush and the PC redirection happen together, just as in the zero-wait case. For the muldiv unit the condition is equivalent to the previous one, because muldiv occupies the EX stage and a branch cannot be there at the same time.

## 6. How the Test Proves the Fix

The entity test runs the core against a simulated SDRAM that responds after 0 to 9 wait cycles. The program executes an SDRAM load followed immediately by a taken branch that skips **three** instructions.

| Core version | Result |
| :--- | :--- |
| With the fix | Passes across all latencies |
| Without the fix | Fails because the register modified by the skipped instructions holds 255 instead of 1 |

The branch must skip more than one instruction. With only one, the target matches the address the PC was already fetching and the error stays hidden, as shown in Section 3.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
