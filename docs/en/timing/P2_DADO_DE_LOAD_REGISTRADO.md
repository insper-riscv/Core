# Step F.P2: load data registered at the end of WB

## 1. Summary

| | |
| :--- | :--- |
| Problem | The data read from memory went through the word crossing, the byte alignment and the sign extension in WB, and went straight to the forwarding of the EX stage, the ALU and the exception decision, in the same cycle (6.9 ns of an 18.5 ns loop) |
| Change | The final WB data is registered (WB2 register), and the forwarding and the register file write come from that register |
| Effect on behavior | A load followed by an instruction that uses it waits one more cycle |
| Hardware | 32 data flip-flops, one write flip-flop and five of the destination index, all enabled by the MEM/WB advance |

## 2. Path before and after

| Stage | Before | After |
| :--- | :--- | :--- |
| Forwarding sources to EX | EX/MEM, MEM/WB and the combinational WB output | EX/MEM, MEM/WB and the WB2 register |
| Tail of the path that starts at the RAM read | Read, alignment, extension, forwarding, ALU, exception, clearing | Read, alignment, extension and the WB2 register |
| Register file write | Combinational WB output | WB2 register |

With the instruction stalled in MEM, the synchronous memory starts answering the address of the stalled instruction, so the data of a load in WB is only valid in the first cycle of a stall; the following cycles repeat the data of the previous cycle (previous-data register and its selector).

## 3. Cost in cycles per instruction

An instruction that depends on the immediately preceding load waits two stall cycles instead of one. Without an immediate dependency there is no cost. The `CoreLoadUse` test measures event 8 (load-dependency stall) at two stalls per dependent pair, and the `sdram-load-use` kernel of the baseline (Insper-RISC-V, `docs/pt-br/platform/timing/`) counts one stall per iteration, because the cache wait absorbs the other cycle.

$$
\text{CPI}_{\text{after}} = \text{CPI}_{\text{before}} + f_{\text{load-use}}
$$

where $f_{\text{load-use}}$ is the fraction of instructions that are the immediate use of a load. The step is only worth it if the frequency gain exceeds that term, and the acceptance criterion is frequency divided by CPI.

## 4. Guarantees and how they are verified

| Guarantee | Verification |
| :--- | :--- |
| The dependent of a load receives the aligned and extended data, for every width and offset | `CoreLoadUse` test (nine loads, each with its user in the next instruction) and the `CoreMisaligned`, `CoreSdramStall` and `ExtenderRAM` tests |
| A stall in MEM does not swap the instruction the forwarding sees | `CoreSdramStall` and `CoreLoadStall` tests (WB2 advances together with MEM/WB) |
| The dependent waits exactly two cycles, and each stall is counted once | `CoreLoadUse` and `CoreZihpm` tests (event 8) |

## 5. Measurement

The RTL of this step is the one measured in `P1_EXCECAO_DE_ACESSO_EM_MEM.md`, section 4. The load data segment (6.9 ns of the 18.5 ns loop before the step) does not appear among the worst core paths: the worst core-to-core paths start at `ID/EX r_imm`, `EX/MEM r_alu_out` and `EX/MEM r_we_ok` and end at the CSRs, the counters and the PC, with 3.9 to 5.3 ns of slack at 50 MHz, and none of them goes through the WB data.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
