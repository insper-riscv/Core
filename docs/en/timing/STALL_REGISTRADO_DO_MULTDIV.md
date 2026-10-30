# Multiplier and Divider Stall Driven by a Flip-Flop

## 1. Summary

The multiply and divide unit (RV32M) holds the whole pipeline while it computes. The signal that does this, the M stall, comes from a flip-flop of its own, and only the first cycle of an operation is combinational. The behavior visible to the core does not change; what changes is the path the signal takes to the pipeline registers.

| | |
| :--- | :--- |
| Problem | The completion pulse of the multiplier and the divider entered the pipeline stall through a chain of 7 logic levels, and that chain was among the paths that violate timing when the core clock rises |
| Change | The M stall is the OR of a one-cycle combinational start with a flip-flop that holds the busy state of the previous cycle |
| Effect on behavior | None: the stall has the same value in every cycle |
| Effect on timing (100 MHz, slow model) | The worst path leaving the multiplier goes from −2.3 ns to +2.0 ns, and the divider from −2.5 ns to +2.2 ns |
| Verification | Core entity tests (17 groups) and a 98-program simulation suite, with no failures |

## 2. How the M stall works

The M unit runs in the EX stage and needs several cycles: 33 for multiplication (Booth) and 34 for division (non-restoring). During that time EX and the stages before it stay stopped.

| Cycle | What the unit does | Stall |
| :--- | :--- | :--- |
| $t_0$ | A valid M instruction reaches EX; the start pulse rises | rises in the same cycle (combinational) |
| $t_0+1$ to $t_d-1$ | The loop adds, subtracts and shifts once per cycle | continues |
| $t_d$ | The completion pulse rises and the result is captured | continues |
| $t_d+1$ | The pipeline advances | falls |

The stall must rise already in $t_0$: if it rose one cycle later, the M instruction would pass through EX without waiting. This is why the first cycle stays combinational.

## 3. Why the stall was on the critical path

The M stall controls the write of the PC and of the pipeline registers. In a stalled cycle the PC does not advance, and no branch, trap return or `mret` may redirect the flow. The signal coming from the completion pulse crossed, in sequence:

| Level | Logic |
| :--- | :--- |
| 1 to 2 | OR of the M busy and completion signals to form the stall |
| 3 | PC write enable |
| 4 | Decision to take the `mret` (valid only while the pipeline moves) |
| 5 to 6 | PC enable and ID/EX register enable |
| 7 | Selection of the `rs1` value entering ID/EX |

With a short period, this chain of 7 logic levels, with routing of up to 1.7 ns between levels, adds up to about 12 ns and violates timing. The part the change removes is the first two levels: the completion pulse stops being an input of the stall logic.

The multiplier and divider loop is not the limit. In a 20 ns period they have 11.4 ns (multiplier) and 14.2 ns (divider) of slack, which gives an isolated limit of about 116 MHz and 172 MHz in the slow model. What limits is the stall control, not the arithmetic.

## 4. The change

The M stall becomes

$$
\text{stall}(t) = \text{start}(t) \;\lor\; \text{active}(t), \qquad \text{active}(t) = \text{busy}(t-1)
$$

where $\text{start}(t)$ is the combinational start pulse (one cycle) and $\text{busy}$ is the OR of the multiplier and divider busy signals. The flip-flop holds the $\text{busy}$ of the previous cycle.

The equivalence with the stall that uses the completion pulse directly follows from how long $\text{busy}$ lasts in each cycle of the operation:

| Cycle | busy | completion | stall with the completion pulse | stall with the flip-flop |
| :--- | :--- | :--- | :--- | :--- |
| $t_0$ | 1 (start) | 0 | 1 | 1 (start) |
| $t_0+1$ to $t_d-1$ | 1 | 0 | 1 | 1 (busy of the previous cycle) |
| $t_d$ | 0 | 1 | 1 | 1 (busy of $t_d-1$) |
| $t_d+1$ | 0 | 0 | 0 | 0 (busy of $t_d$ is 0) |

The busy signal of the multiplier and the divider falls in the same cycle in which the completion pulse rises, and is 1 in the cycle before. So busy delayed by one cycle covers exactly the completion cycle.

## 5. Measurements

Quartus timing analysis (slow model, 85 °C) of the `internal-mem` platform with the core clock at 100 MHz.

| Path | Without the flip-flop | With the flip-flop |
| :--- | :--- | :--- |
| Worst leaving the multiplier | −2.304 ns | +1.981 ns |
| Worst leaving the divider | −2.486 ns | +2.219 ns |
| M paths among the 800 worst | present | none |
| Worst path of the project | −7.623 ns | −7.267 ns |

The worst path of the project goes from the data RAM read to the `reg_ex_mem` and `reg_id_ex` registers, and keeps violating at a 10 ns period. That path is independent of M.

Functional verification:

| Verification | Result |
| :--- | :--- |
| Core entity tests | 17 groups, 0 failures |
| Simulation suite (`internal-mem` platform) | 98 of 98 |

## 6. Cost and limits

| Item | Value |
| :--- | :--- |
| Hardware | 1 flip-flop |
| Latency of an M operation | 33 and 34 cycles, unchanged |
| New signals | none in the module contract; the stall remains the `o_stall` output |

The change does not raise the core frequency by itself: it removes M from the list of paths that violate timing. The limit becomes the RAM read path and the crossing between the three phase-shifted pipeline clocks.
