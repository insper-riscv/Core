# Load in WB Overwritten by Another Load While the Pipeline Is Stalled

## 1. Summary

While the multiply and divide unit (M) computes, the whole pipeline stalls and the MEM/WB register holds its instruction. A load held in WB wrote its destination register on every stalled cycle. After the first cycle, the data memory answered for the address of the load stopped in MEM, so the register received the word of the wrong load.

| | |
| :--- | :--- |
| Symptom | The destination of a load holds the word of the next load after an `mul`, `div` or `rem` |
| Condition | Two loads in a row from the internal RAM or from flash port 2, followed by an M instruction that does not depend on the second load |
| Fix | WB repeats the datum of its first cycle while it is held |
| Test | `CoreLoadStall`, a core test with `has_m = true` and synchronous RAM and flash models |

## 2. How the Data of a Load Reaches WB

The internal RAM and flash port 2 answer one cycle after the address, and the read enable of MEM stays high while the access is in MEM. In the cycle in which a load is in WB, the memory output is the word of its address, presented in the previous cycle.

| Stage | Instruction | What the memory presents |
| :--- | :--- | :--- |
| MEM | second load | its address, read enable high |
| WB | first load | the word of the first address, valid in this cycle only if the pipeline advanced |

## 3. What Went Wrong

The M instruction in EX stalls the pipeline on its first cycle, with the first load in WB and the second in MEM. The cycles go as follows:

| Cycle | WB | Word on the data bus | Register of the first load |
| :--- | :--- | :--- | :--- |
| $t_0$ | first load | word of the first load | correct value written |
| $t_0 + 1$ to the end of the stall | first load (held) | word of the second load | overwritten on every cycle |

The register file is written whenever the instruction in WB has `we_reg` set, and MEM/WB does not change while the stall lasts. The forwarding path from WB received the same wrong word.

A bubble in MEM hides the problem: its read enable is low, the memory keeps its output, and the repeated write carries the same word. This is the case when the M instruction uses the second load, because the load-use bubble goes into MEM.

## 4. The Fix

A flip-flop records that the previous cycle was a stall of EX and MEM, and a register keeps the datum WB delivered in the previous cycle. While the flip-flop is set, WB delivers the kept datum:

$$
\text{wb\_data}(t) =
\begin{cases}
\text{wb\_data}(t-1) & \text{if } \text{base\_run}(t-1) = 0 \\
\text{raw datum of WB} & \text{otherwise}
\end{cases}
$$

The first cycle of an instruction in WB always takes the raw datum, which is the valid one. Every later cycle in which it is held, and the cycle in which the stall ends, repeat it. The register file and the forwarding path read the same signal.

## 5. Cost

| Item | Value |
| :--- | :--- |
| Hardware | 33 flip-flops and a 32-bit 2-to-1 multiplexer |
| Timing | one more multiplexer level on the path from the data memory to the forwarding and the register file |
