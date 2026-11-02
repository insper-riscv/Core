# Formal verification

The formal proofs of the Core run in SymbiYosys over the Verilog netlist that GHDL synthesizes from each entity, with the properties written in SystemVerilog around it (`formal/*_props.sv`). The same set of proofs runs with more than one engine, and the CI only passes when the engines that answered agree with each other and with the wanted result. This document describes what is proved, the engines, the result file and the rule that decides the `formal` check.

## 1. What is proved

| Block | Properties | Kinds of proof |
| :--- | :--- | :--- |
| `csr_file` | `csr_file_props.sv` | induction, cover |
| `trap_unit` | `trap_unit_props.sv` | induction, cover, with and without the address check and Zicclsm |
| `counter64` | `counter64_props.sv` | induction, cover |
| `muldiv_fusion` | `muldiv_fusion_props.sv` | BMC, cover |
| `csr_file` with Zicntr | `csr_cntr_props.sv` | BMC, cover |
| `csr_file` with Zihpm | `csr_hpm_props.sv` | BMC, cover |

Each deliberate defect of the VHDL (a mutant) must make a proof fail, and that wanted result is `fail`. A proof by induction or by BMC wants `pass`, and a cover wants `pass` when the goal is reachable.

## 2. Engines

The engine is chosen by the `FORMAL_ENGINE` variable.

| Engine | What it is | Induction | BMC | Cover | Typical time of `make formal` |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `bitwuzla` (default) | SMT solver for bit-vectors, through the `smtbmc` engine | yes | yes | yes | about 40 s |
| `boolector` | SMT solver for bit-vectors, through the `smtbmc` engine | yes | yes | yes | about 45 s |
| `yices` | SMT solver, through the `smtbmc` engine | yes | yes | yes | about 60 s |
| `abc-bmc3` | the bounded model checker of ABC, through the `abc bmc3` engine | no | yes | no | about 35 s |

`abc-bmc3` only checks bounded properties of designs with registers. It skips the proofs by induction, the covers and the combinational blocks (`trap_unit`, which ABC refuses), which leaves 21 of the 47 proofs without an answer from it. A skip is not a failure: it is a proof the engine does not do.

The times are from one run with 4 CPUs.

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

The workflow has one job per engine, `formal - <engine>` (`yices`, `bitwuzla`, `boolector` and `abc-bmc3`), which runs `make formal FORMAL_ENGINE=<engine>` and uploads the result and the logs as an artifact. The `formal` job waits for all of them, downloads the artifacts and runs the aggregator. Only the `formal` job is a required check of the default-branch ruleset, so an engine that breaks does not block the merge while another one decides, and a counterexample found by any engine blocks it.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../LICENSE).
