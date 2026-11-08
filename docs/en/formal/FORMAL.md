# Formal verification

The formal proofs of the Core run in SymbiYosys over the Verilog netlist that GHDL synthesizes from each entity, with the properties written in SystemVerilog around it (`formal/*_props.sv`). The same set of proofs runs with more than one engine, and the CI only passes when the engines that answered agree with each other and with the wanted result. This document describes what is proved, the engines, the result file and the rule that decides the `formal` check.

## 1. What is proved

| Block | Properties | Kinds of proof |
| :--- | :--- | :--- |
| `csr_file` | `csr_file_props.sv` | induction, cover |
| `trap_unit` | `trap_unit_props.sv` | induction, cover, with and without the address check and Zicclsm, and with the illegal instruction before the misaligned target (Table 17) |
| `csr_file` with interrupts | `csr_irq_props.sv` | induction, BMC, cover, with the entry condition and priority and the `mtvec` modes |
| `trap_unit` with an interrupt | `trap_unit_props.sv` | induction, cover |
| `stage_ex` with interrupts | `stage_ex_irq_props.sv` | induction, cover, with `mepc`, `mcause`, `MIE`, the next PC and the null effect of an aborted CSR access |
| `alu` | `alu_props.sv` | combinational equivalence, cover |
| `trap_unit` with access faults | `trap_af_props.sv` | induction, cover, with the order and `mtval` mutants |
| `csr_file` with `time_external` | `csr_time_props.sv` | BMC, cover |
| `muldiv_fusion` | `muldiv_fusion_props.sv` | BMC, cover |
| `csr_file` with Zicntr | `csr_cntr_props.sv` | BMC, cover |
| `csr_file` with Zihpm | `csr_hpm_props.sv` | BMC, cover, with 29, 5, 4, 3 and 2 real counters and widths from 0 to 64 bits |
| `csr_file` with Sscofpmf | `csr_ofp_props.sv` | BMC, cover, with `OF`, `MINH`, `LCOFIP`, `LCOFIE` and the timer priority over the overflow, on a symbolic index |
| `zicond_unit` | `zicond_props.sv` | induction, cover |
| `zicond_decode` | `zicond_decode_props.sv` | induction, cover |
| `core` with Zicsr (`o_trap_take`) | `core_trap_take_props.sv` | BMC, cover |

Each deliberate defect of the VHDL (a mutant) must make a proof fail, and that wanted result is `fail`. A proof by induction or by BMC wants `pass`, and a cover wants `pass` when the goal is reachable.

## 2. Engines

The engine is chosen by the `FORMAL_ENGINE` variable.

| Engine | What it is | Induction | BMC | Cover | Typical time of `make formal` |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `bitwuzla` (default) | SMT solver for bit-vectors, through the `smtbmc` engine | yes | yes | yes | 216 s |
| `boolector` | SMT solver for bit-vectors, through the `smtbmc` engine | yes | yes | yes | 226 s |
| `yices` | SMT solver, through the `smtbmc` engine | yes | yes | yes | 376 s |
| `abc-bmc3` | the bounded model checker of ABC, through the `abc bmc3` engine | no | yes | no | 346 s |

`abc-bmc3` only checks bounded properties of designs with registers. It skips the proofs by induction, the covers and the combinational blocks (`alu`, `trap_unit` and the Zicond blocks, which ABC refuses), which leaves 53 of the 154 proofs without an answer from it. A skip is not a failure: it is a proof the engine does not do. The induction proofs of `mip`, `mie` and `mstatus.MIE` therefore have one more bounded form of 6 cycles (`csri_bounded`), the only one it answers.

The times are from one run with 4 CPUs and 8 GB, on a lab workstation with other jobs running in parallel.

## 3. Running

```bash
make formal                          # the default engine (bitwuzla)
make formal FORMAL_ENGINE=yices      # another engine
FORMAL_TIMEOUT=300 make formal       # limits each proof to 300 s (900 s by default)
```

The `formal/run.sh` script classifies the exit code of `sby` per proof.

| `sby` exit code | Verdict | Meaning |
| :---: | :--- | :--- |
| 0 | `pass` | the property holds (or the cover is reachable) |
| 2 | `fail` | there is a counterexample (or the cover is unreachable) |
| other | `error` | the tool did not reach a verdict: timeout (124), error (16) or unknown (4) |
| | `skip` | the engine does not do this kind of proof |

An `error` fails the run of the engine, even when the wanted verdict is `fail`, so that a broken engine does not pass for a caught mutant.

## 4. Result file

Each run writes `build/formal/result-<engine>.tsv`, one line per proof, with tab-separated columns.

| Column | Content |
| :---: | :--- |
| 1 | identifier of the proof (the same in every engine) |
| 2 | wanted verdict (`pass` or `fail`) |
| 3 | verdict of the engine (`pass`, `fail`, `error` or `skip`) |
| 4 | exit code of `sby` |
| 5 | time of the proof in milliseconds |
| 6 | description of the proof |

## 5. The aggregator

The `formal/aggregate.sh <directory>` script reads every `result-<engine>.tsv` of the directory and decides, per proof, from the `pass` and `fail` verdicts. An `error` and a `skip` do not count as an answer.

| Situation of the proof | Result |
| :--- | :--- |
| no engine answered | fails |
| one engine said `pass` and another said `fail` | fails (the engines disagree) |
| the engines that answered agree, but differ from the wanted verdict | fails |
| the engines that answered agree with the wanted verdict | passes |

An engine that wrote no result counts as `error` in every proof. The aggregator exits with code 1 if some proof fails or if there is no result file, and writes the table of proofs by engines to the output and to the summary of the GitHub Actions job.

The tests of the aggregator run with `bash formal/aggregate_test.sh`.

## 6. In the CI

The workflow has one job per engine, `formal - <engine>` (`yices`, `bitwuzla`, `boolector` and `abc-bmc3`), which runs `make formal FORMAL_ENGINE=<engine>` and uploads the result and the logs as an artifact. The `formal` job waits for all of them, downloads the artifacts and runs the aggregator. Only the `formal` job is a required check of the default-branch ruleset, so an engine that breaks does not block the merge while another one decides, and a counterexample found by any engine blocks it. In a push to `main` that reuses the result of a pull request that already passed, the engines and `formal` are skipped together, like the other required checks.

## 7. A warning is an error

Any warning from GHDL, Yosys or SymbiYosys makes `formal/run.sh` fail, in the proofs and in the mutants. The guard lives in `formal/warnings.sh`: the script scans the output of each tool after it ends and, for every line with the word `warning` (case-insensitive, whole word or plural), prints `formal: WARNING treated as error: <file>:<line>:<text>` and fails the run at the end. Names such as `warning_count` and the Yosys summary `Warnings: 0` do not count.

A warning means code outside the norm or at its limit, so the fix is in the VHDL or in the properties, never in an option that hides the warning (`-Wno-*`). Each mutant is analyzed in the place of the unit it replaces, so no entity is defined in two files.

The `abc-bmc3` engine has one exact exception, only for the messages ABC itself prints when it reads the AIGER file it receives (the count of outputs read as constraints, which are the assumptions and the clock of the `clk2ff` step, and `The network has no constraints.`), and only in the log of that engine. The warnings that the clock is an undriven bit are not accepted: the script of the proof flattens the design and purges the aliases of the clock before the AIGER file is written. One more message, `The network is combinational.`, is accepted only in the proof that the engine refuses for being combinational and that the script records as `skip`. `yices`, `bitwuzla` and `boolector` have no exception, and any other warning of `abc-bmc3` still fails.

The tests of the guard run together with those of the aggregator, with `bash formal/aggregate_test.sh`.

## 8. Interrupt proofs by induction

A property that keeps a model of a register of the unit outside it cannot be proven by induction alone, because the induction starts from any state of the unit and the model is free. The fix is an invariant saying that the model is the register. `formal/run.sh` connects wires of `props` to nets of the flattened netlist (`PROBES`, the Yosys command `connect`), without changing the VHDL, and the proof asserts, at every cycle without reset, that the model is the register.

| Proof | Registers connected | Property by induction |
| :--- | :--- | :--- |
| `csri_safety` | mask bits of `mie`, `mstatus.MIE` and `MPIE`, BASE and MODE of `mtvec` | `mip` reads the three lines at positions 3, 7 and 11, `mie` keeps only those bits, a write to `mip` changes nothing, `o_irq_pending` is lines and mask, `o_irq_take` needs `mstatus.MIE`, the cause has the priority external, software, timer, and `mtvec` keeps BASE and MODE |
| `csrio_safety` | the same | without `has_interrupts` the lines are ignored and `mip` and `mie` read zero |

The entry itself is proven by `stage_ex_irq_props.sv` and `trap_unit_props.sv` (both by induction): `mepc` is the address of the aborted instruction, `mcause` carries the cause and the line, `MIE` goes to 0 and `MPIE` to 1, the next PC is BASE or the vector, and the interrupt wins over every exception and `MRET`. The restore of `MIE` by `MRET` is proven by induction in `csr_mstatus`. The proofs of the counters (`csr_cntr_props.sv`, `csr_hpm_props.sv`) and of the fusion stay bounded, and the reason is in the comments of each file.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
