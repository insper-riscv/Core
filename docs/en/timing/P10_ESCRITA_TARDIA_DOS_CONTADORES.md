# Step F.P10: late gate on the CSR counter writes

🌐 [Português](../../pt-br/timing/P10_ESCRITA_TARDIA_DOS_CONTADORES.md) · [English](P10_ESCRITA_TARDIA_DOS_CONTADORES.md)

## 1. Summary

| | |
| :--- | :--- |
| Problem | The write enable of the high half of `minstret` (and of `mcycle`, `mcountinhibit` and the Zihpm bank) came from the valid-write signal shared by every CSR, with a fanout of 293, and that signal waited for `pipe_run` (fanout 337), which comes from the classification of the data address in MEM: ten logic levels, with 1.2 and 1.8 ns of routing in the two high-fanout hops, and 10.5 ns of data in a 10 ns period |
| Change | `csr_file` splits the counter writes into an early selection (address and write effect, both from registers) and a late gate of its own (`i_commit`, no trap and no `mret`) that enters the last logic layer and fans out only to the counters |
| Effect on behavior | None: the enables hold the same values as before in every cycle |
| Effect on cycles per instruction | None |

## 2. Equivalence

The addresses of `mcycle`, `mcycleh`, `minstret`, `minstreth` and `mcountinhibit` are always known and read-write when the profile includes Zicntr, so the known-address and read-only tests of the general decoder are constant true at those addresses. For the Zihpm bank, the known address is contained in the bank's own selection, which already requires the range and the present counter; the read-only test is still done outside the bank.

$$
we_{cntr} = commit \cdot \overline{trap} \cdot \overline{mret} \cdot write\_effect \cdot (addr = A_{cntr})
$$

## 3. Verification

| Guarantee | Verification |
| :--- | :--- |
| The writes, the pending retire and the cancellation of `minstret` stay the same | Formal proofs of `csr_file` and of the counters, and the Zicntr and Zihpm core tests |
| The path stopped being critical | Setup slack of `csr_file` in Quartus, in the table of the pull request that brought this change |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
