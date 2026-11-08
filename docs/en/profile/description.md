# Core Profiles

A profile is a combination of RISC-V extensions that the `core` implements, selected by its input generics. This document describes the files that define the profiles, the rules that generate the full matrix, and the reference profiles kept in `profiles/`.

## 1. Files

| File | Content |
| :--- | :--- |
| `profiles/matrix.yaml` | The bases (RV32I and RV32E), the extensions with the generic that turns each one on, and the rules between them |
| `profiles/<profile>.yaml` | One reference profile, with `extensions`, `top`, `generics` and the `sources` list in GHDL dependency order |
| `paths.yaml` | A `provides` section with the sources of each component of `src/` and the dependencies between components |

## 2. Matrix

The matrix is the single source of the valid profiles. The command `riscv-tools profiles --spec profiles/matrix.yaml` expands it into 480 profiles, and the `profile-matrix` target of the `Makefile` elaborates each one with its generics.

### 2.1. Bases and extensions

| Item | Generic | Note |
| :--- | :--- | :--- |
| RV32I | `has_e => false` | Base with 32 registers |
| RV32E | `has_e => true` | Base with 16 registers |
| Zicclsm | `has_zicclsm` | Misaligned accesses handled in hardware |
| Zicsr | `has_zicsr` | CSR bank and traps |
| Zicntr | `has_zicntr` | Implies Zicsr |
| Zihpm | `has_zihpm` | Implies Zicsr; parameterized by `hpm_counters` and `hpm_width` |
| Zifencei | `has_zifencei` | `FENCE.I` instruction |
| Zimop | `has_zimop` | The 40 `mop.r.n` and `mop.rr.n` encodings |
| Zicond | `has_zicond` | `czero.eqz` and `czero.nez` |
| Zmmul | `has_zmmul` | Multiplication without division |
| M | `has_m` | Multiplication and division; implies Zmmul |

### 2.2. Rules between extensions

| Rule | Effect |
| :--- | :--- |
| M and Zmmul are mutually exclusive | The profile name carries only one of the two |
| Zicsr is exclusive with Zicntr and with Zihpm | The counters are CSRs, so the name of a profile with either never cites Zicsr |
| Zicntr and Zihpm can coexist | The name carries `zicntr_zihpm` |

### 2.3. Profile name

The name starts with the base (`rv32i` or `rv32e`), with `m` appended directly when M is on, and then the names of the other extensions in lower case, in the order of the `extensions` list of `matrix.yaml`. A test profile outside the generated names carries the suffix `_reduced`.

## 3. Reference profiles

| Profile | Extensions | Generics besides the extension ones |
| :--- | :--- | :--- |
| `rv32i` | I | `has_m => false` |
| `rv32i_zmmul` | I, Zmmul | |
| `rv32im` | I, M | |
| `rv32im_zicsr` | I, M, Zicsr | |
| `rv32im_zicsr_zifencei` | I, M, Zicsr, Zifencei | |
| `rv32im_zicclsm_zicntr_zifencei` | I, M, Zicclsm, Zicntr, Zifencei | |
| `rv32im_zicclsm_zicntr_zihpm_zifencei` | I, M, Zicclsm, Zicntr, Zihpm, Zifencei | `hpm_counters => 29`, `hpm_width => 64` |
| `rv32im_zicclsm_zicntr_zihpm_zifencei_reduced` | the same | `hpm_counters => 4`, `hpm_width => 40` |
| `rv32im_zimop` | I, M, Zimop | |
| `rv32im_zicond` | I, M, Zicond | |

Every reference profile has `top: core` and analyzes the same extension units that the `core` instantiates directly. Units disabled by a generic leave the elaboration when the `generate` statements are evaluated, so the `sources` list does not change with the generic.

## 4. Components of `src/`

The `provides` section of `paths.yaml` splits `src/` into components, one per folder, plus the `constants` component, which gathers the constant packages of every folder because the decoders and units of one folder read the constants of the others.

| Component | Depends on |
| :--- | :--- |
| `constants` | none |
| `shared`, `I-E`, `M`, `Zicclsm`, `Zicntr`, `Zicond`, `Zifencei`, `Zimop` | `constants` |
| `Zihpm` | `constants`, `Zicntr` |
| `Zicsr` | `constants`, `Zicntr`, `Zihpm` |
| `core` | all the previous ones |

Each component lists in `requires` the blocks of `src/common/` (the Common-Components submodule) it uses, as `Common-Components/<component>`, and `riscv-tools sources core` resolves them in the manifest of the submodule. The order of the sources inside each component is the GHDL dependency order, and `check-paths` confirms that every listed file exists.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
