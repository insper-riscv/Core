# Step F.P7: barrier registers clear only the control bits

🌐 [Português](../../pt-br/timing/P7_FLUSH_SO_NOS_BITS_DE_CONTROLE.md) · [English](P7_FLUSH_SO_NOS_BITS_DE_CONTROLE.md)

## 1. Summary

| | |
| :--- | :--- |
| Problem | The discard on a branch, jump or trap is born at the end of the EX loop (ALU comparator, `o_branch_taken`) and cleared about 200 bits of `ID/EX` synchronously, plus fields of `IF/ID` and `EX/MEM`. The clear network, with a high fan-out, added 4 to 4.5 ns to the EX loop |
| Change | The four registers (`reg_if_id`, `reg_id_ex`, `reg_ex_mem` and `reg_mem_wb`) clear only the control bits on `i_flush` or `i_rst`. The data fields only have the enable (`i_en`) |
| Effect on behavior | None. A bubble leaves the registers with `o_valid` and the side-effect enables at zero, and every use of a data field depends on them |
| Effect on cycles per instruction | None |

## 2. Fields of each register

| Register | Cleared by `i_flush` and `i_rst` | Enable only |
| :--- | :--- | :--- |
| `reg_if_id` | valid bit, `opcode` field of the instruction | `pc`, `pc4`, bits `[31:7]` of the instruction |
| `reg_id_ex` | valid bit, `rs1` and `rd` indices, selectors, ALU code and selection, forwarding matches, `we_reg`, `we_ram`, `re_ram`, `en_ram`, `is_csr`, `is_muldiv`, `illegal`, `opcode`, `funct3` | `pc`, `pc4`, `rs1_val`, `rs2_val`, `imm` |
| `reg_ex_mem` | valid bit, `rd`, `we_reg`, `we_ok`, memory enables, extension mode, write-back selector, address classification | `pc`, `funct3`, `alu_out`, `store_data`, `byte_mask` |
| `reg_mem_wb` | valid bit, `rd`, `we_reg`, `we_ok`, extension mode, write-back selector, address classification | `alu_out` |

## 3. Why the value of a bubble never has an effect

| Use of the data field | Condition that blocks it |
| :--- | :--- |
| Branch, jump and exception in EX | `i_valid`, which comes from `o_valid` of `ID/EX` |
| Register file write and forwarding | `we_reg` and `we_ok`, cleared by the flush |
| Memory access in MEM and the `mepc` write of a MEM exception | valid bit and memory enables of `EX/MEM`, cleared by the flush |
| Decode in ID of a discarded instruction | `i_ifid_valid` in the hazard detection and in the valid bit handed to `ID/EX`, and a zeroed `opcode`, which decodes to no effect |

## 4. Verification

| Guarantee | Verification |
| :--- | :--- |
| Each register clears only the controls and holds or captures the data according to `i_en` | Entity tests `RegIfId`, `RegIdEx`, `RegExMem` and `RegMemWb` |
| The core behaves the same | Every core test (`cores/`), with the same cycle count and the same final RAM content as before the change |
| The formal proofs still hold | `make formal` |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
