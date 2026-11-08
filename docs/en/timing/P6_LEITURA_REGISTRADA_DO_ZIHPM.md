# Step F.P6c: registered read of the Zihpm bank

🌐 [Português](../../pt-br/timing/P6_LEITURA_REGISTRADA_DO_ZIHPM.md) · [English](P6_LEITURA_REGISTRADA_DO_ZIHPM.md)

## 1. Summary

| | |
| :--- | :--- |
| Problem | The read of a Zihpm counter went through a 29-counter multiplexer (nine logic levels, with 1.3 to 1.9 ns of routing between them), went on to the instruction result and, in `csrrs`, `csrrc` and `csrrw`, came back to the write of the destination counter: 12.3 ns of data in a 10 ns period |
| Change | The bank (`hpm_counter_bank`, generic `registered_read`) registers the value read; the CSR instruction that accesses the bank waits one cycle in EX (`o_csr_wait` of `stage_ex`, added to the pipeline stall), reads the registered value in the next cycle and writes from it |
| Effect on behavior | The value read is the counter in the wait cycle, in which every older instruction has already been counted and the instruction itself has not; the writes are the same |
| Effect on cycles per instruction | One more cycle per CSR instruction that accesses `mcountinhibit`, `mhpmeventK`, `mhpmcounterK` or `mhpmcounterKh` (and the mirrors); zero in other programs |

## 2. Guarantees and how they are checked

| Guarantee | Check |
| :--- | :--- |
| The read returns the right value and the counters count the same events | Entity tests of the `csr_file` and the bank (combinational mode, unchanged) and Zihpm core tests (`cores/zihpm`), which run the registered bank |
| The write happens once, in the cycle the instruction advances | `csr_commit` depends on `i_pipe_run`, which is zero in the wait cycle |
| The cost is one cycle per read | Core test `test_a_bank_read_costs_one_cycle`: 16 back-to-back reads of `mhpmcounter3` take exactly 16 cycles more than 16 reads of `mscratch` (`mcycle` difference) |
| A read right after a write and the `csrrs` see the right value | Core test `test_a_read_right_after_a_write_sees_the_new_value` |
| The read of a CSR right after a bank counter does not receive its bits | Core test `test_a_counter_read_does_not_leak_into_the_next_csr_read` |
| The registered bank returns the value of the address cycle | Entity test `HpmCounterBankRegistered` (5 tests) |
| `mcountinhibit` and `mhpmevent` still hold | Formal proofs of the `csr_file` (combinational mode) and core tests |

## 3. Measurement

The values are in [docs/en/platform/timing/FRENTE-F-ONDA2.md of Insper-RISC-V](../../../../docs/en/platform/timing/FRENTE-F-ONDA2.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
