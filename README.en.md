# Core

🌐 [Português](README.md) · [English](README.en.md)

RISC-V RV32 processor in VHDL-2008 organized as an in-order 5-stage pipeline (IF, ID, EX, MEM, and WB), modularized by ISA extension (`I`, `M`, `Zicsr`, and `Zifencei`) under a single top-level entity (`core`), accompanied by per-entity unit tests via cocotb/GHDL and formal verification via SymbiYosys.

## 1. Documentation

- [AUTHORS.en.md](AUTHORS.en.md): authors with commits in the repository, with name and GitHub account.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md): mandatory contribution rules, VHDL-2008 standard (`--std=08`), naming conventions, `i_`/`o_` port prefixes, file headers, docstrings, and documentation rules.
- [ISA/I/instructions.md](docs/en/ISA/I/instructions.md): RISC-V manual requirements for the RV32I base (programmer state, formats, the 37 instructions with encoding and semantics, `FENCE`, `ECALL`, `EBREAK`) and the Core behavior in each case.
- [ISA/I/description.md](docs/en/ISA/I/description.md): how the Core implements the RV32I base, with stages, control decoder, ALU, immediate and load extenders, store manager, forwarding and hazards.
- [ISA/I/construcao-incremental.md](docs/en/ISA/I/construcao-incremental.md): 32-bit RISC-V instruction formats and incremental datapath progression for the 37 base RV32I instructions.
- [ISA/I/ULA.md](docs/en/ISA/I/ULA.md): operation code, shared adder-subtractor, branches, shifters, and result selection of the ALU.
- [ARCHITECTURE.md](docs/en/ARCHITECTURE.md): 5-stage pipeline microarchitecture, per-stage responsibilities, forwarding paths, load-use hazard detection, stall, flush, and support for the `M`, `Zicsr`, and `Zifencei` extensions.
- [PIPELINE_ARCHITECTURE_GUIDE.md](docs/en/PIPELINE_ARCHITECTURE_GUIDE.md): detailed reference of inter-stage interconnect signals, synchronous barriers (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`), stall and flush equations, and branch resolution.
- [ISA/I/DECODER.md](docs/en/ISA/I/DECODER.md): decoding table of the base control unit, with the control signals of the 37 base RV32I instructions and the behavior of any other instruction as a `NOP`.
- [contracts/01-contrato-de-extensao.md](docs/en/contracts/01-contrato-de-extensao.md): extension directory contract, profile manifests (`profiles/*.yaml`), and single integration point for new extensions in the top-level entity.
- [contracts/02-barramento-e-memoria.md](docs/en/contracts/02-barramento-e-memoria.md): instruction and data bus protocol (byte addressing, byte enables, wait handshake for variable-latency memory, and instruction cache).
- [ISA/Zicclsm/instructions.md](docs/en/ISA/Zicclsm/instructions.md) and [ISA/Zicclsm/description.md](docs/en/ISA/Zicclsm/description.md): what the profiles specification requires of Zicclsm and the hardware execution of misaligned loads and stores, access classification, regions covered in each memory map, and the two-step access that crosses a word.
- [FORMAL.md](docs/en/FORMAL.md): formal proofs, solver engines, the result file of each engine and the rule of the aggregator that decides the `formal` CI check.
- [ISA/E/description.md](docs/en/ISA/E/description.md): the `has_e` generic that chooses the 32-register file (RV32I) or the 16-register file (RV32E), the illegal instruction with `x16` to `x31`, and the `ilp32e` ABI.
- [ISA/Zicsr/instructions.md](docs/en/ISA/Zicsr/instructions.md) and [ISA/Zicsr/description.md](docs/en/ISA/Zicsr/description.md): the Zicsr extension, with the instructions, encoding and read/write rules required by the manual, and the Core implementation (CSR file, synchronous exceptions, `MRET`, redirection and behavior without Zicsr).
- [ISA/Zicntr](docs/en/ISA/Zicntr/description.md): the base counters `cycle`, `time` and `instret` (Zicntr), with what the manual requires, the 64-bit counter block, instruction retirement, the tick divider and `mcountinhibit`.
- [ISA/Zihpm](docs/en/ISA/Zihpm/description.md): the `hpmcounter` performance counters (Zihpm), with what the manual requires, the organization of the event counters, the counting rule and the event table.
- [ISA/M/instructions.md](docs/en/ISA/M/instructions.md): instructions of the `M` extension according to the RISC-V manual (chapter 11): encoding, division, division by zero and overflow.
- [ISA/M/description.md](docs/en/ISA/M/description.md): how the Core executes `M`: decoder, non-restoring divider, pipeline stall, pair fusion and formal verification.
- [ISA/Zmmul/instructions.md](docs/en/ISA/Zmmul/instructions.md): instructions of the `Zmmul` extension (multiplication only, section 11.1.3 of the manual): encoding and semantics.
- [ISA/Zmmul/description.md](docs/en/ISA/Zmmul/description.md): how the Core executes `Zmmul`: configuration, decoding without division and the Booth multiplier.
- [ISA/Zicond/instructions.md](docs/en/ISA/Zicond/instructions.md) and [ISA/Zicond/description.md](docs/en/ISA/Zicond/description.md): `Zicond` extension (`czero.eqz` and `czero.nez`, chapter 10 of the manual), encoding, semantics and the execution in the Core.
- [ISA/Zifencei/instructions.md](docs/en/ISA/Zifencei/instructions.md) and [ISA/Zifencei/description.md](docs/en/ISA/Zifencei/description.md): the Zifencei extension (`FENCE.I`), manual requirements, regions that go through the instruction cache, execution with and without a write-back data cache, effect on the pipeline and the caches, and cost.
- [ISA/Zimop/instructions.md](docs/en/ISA/Zimop/instructions.md) and [ISA/Zimop/description.md](docs/en/ISA/Zimop/description.md): the Zimop extension (`mop.r.n` and `mop.rr.n`), manual requirements, encoding of the 40 instructions, decoding in the ID stage and verification.
- [ISA/Zihintntl/instructions.md](docs/en/ISA/Zihintntl/instructions.md) and [ISA/Zihintntl/description.md](docs/en/ISA/Zihintntl/description.md): the Zihintntl extension (`ntl.p1`, `ntl.pall`, `ntl.s1` and `ntl.all`), hint encodings and execution as `nop`.
- [ISA/Zihintpause/instructions.md](docs/en/ISA/Zihintpause/instructions.md) and [ISA/Zihintpause/description.md](docs/en/ISA/Zihintpause/description.md): the Zihintpause extension (`pause`), hint encoding and execution as `nop`.
- [MEMORY_WIDTH.md](docs/en/MEMORY_WIDTH.md): rules for the adapter between the Core's 32-bit word and a narrower or wider memory, covering address, byte mask, read, ready signal and interaction with misaligned access.
- [bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md](docs/en/bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md): mathematical analysis of the partial remainder range in non-restoring division and the use of 34 internal bits for unsigned divisors above $2^{31}$.
- [bugs/FLUSH_COM_PIPELINE_PARADO.md](docs/en/bugs/FLUSH_COM_PIPELINE_PARADO.md): analysis of the interaction between branch redirection in EX and global pipeline stall caused by memory wait in MEM.
- [bugs/LOAD_EM_WB_DURANTE_STALL.md](docs/en/bugs/LOAD_EM_WB_DURANTE_STALL.md): analysis of a load held in WB that was overwritten by the next load while the M unit stalls the pipeline.

## 2. Repository Structure

| Path | Contents |
| :--- | :--- |
| `src/common/` | Submodule [Common-Components](https://github.com/insper-riscv/Common-Components): the generic blocks (adder, flip-flop, registers, multiplexers and one-hot decoder) the Core imports |
| `src/shared/` | Core parts used by every profile: type and constant packages, inter-stage barrier registers, base control unit, register file, forwarding and hazard units and PC generator |
| `src/I-E/` | Blocks shared by the RV32I and RV32E bases (the RV32E only cuts the register file to 16), comprising the ALU, immediate extender, memory read extender, and store alignment manager |
| `src/M/` | Integer multiplication and division extension RV32M, containing a dedicated decoder, sequential radix-2 Booth multiplier, 34-bit non-restoring divider, and integration unit |
| `src/Zicsr/` | Machine-mode Control and Status Registers (CSRs) extension and synchronous exception and trap-return (`MRET`) detection unit |
| `src/Zicntr/` | Counters extension: `mcycle`, `minstret`, `time` and the mirrors `cycle`, `instret`, `time`, with the 64-bit counter and the time divider |
| `src/Zicclsm/` | Unit for misaligned access to the main memory (`misaligned_unit`), which splits an access that crosses a word into two steps |
| `src/Zifencei/` | Instruction-memory synchronization extension (`FENCE.I`), with optional write-back data-cache flush handshake support |
| `src/Zicond/` | Conditional zero extension (`czero.eqz` and `czero.nez`), with a decoder in the ID stage and an execution unit in the EX stage |
| `src/Zimop/` | May-Be-Operations extension (`mop.r.n` and `mop.rr.n`), which write zero to `rd` |
| `src/Zihintntl/` | Non-temporal locality hint extension (`ntl.p1`, `ntl.pall`, `ntl.s1` and `ntl.all`), which execute as `nop` |
| `src/Zihintpause/` | Extension of the `pause` hint, which executes as `nop` |
| `src/core/` | Entities for the 5 pipeline stages (`stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb`) and the processor structural top level (`core`) |
| `profiles/` | The profile specification (`matrix.yaml`) and the source manifests of the profiles that prove the core builds without the optional directories (`rv32i.yaml`, `rv32i_zmmul.yaml`, `rv32im.yaml`, `rv32im_zicsr.yaml`, `rv32im_zicond.yaml`, `rv32im_zicsr_zifencei.yaml`, `rv32im_zicclsm_zicntr_zifencei.yaml`, `rv32im_zicclsm_zicntr_zihpm_zifencei.yaml`, `rv32im_zicclsm_zicntr_zihpm_zifencei_reduced.yaml`) in dependency order |
| `formal/` | SystemVerilog properties (`csr_file_props.sv`, `trap_unit_props.sv`), `.sby` configurations, formal verification script via GHDL + Yosys + SymbiYosys, and the aggregator of the engines ([documentation](docs/en/FORMAL.md)) |
| `tests/python/` | Per-entity and top-level integration unit tests in cocotb/GHDL ([documentation](tests/python/README.en.md)) |

## 3. ISA Profiles

The structural top level `core` takes one boolean generic per extension, which enables or disables the extension at elaboration time:

| Extension | Generic | Default | With the generic off |
| :--- | :--- | :--- | :--- |
| M | `has_m` | `false` | M instructions are illegal (cause 2 with Zicsr, `o_trap` without Zicsr) |
| Zmmul | `has_zmmul` | `false` | Multiplication instructions are illegal (cause 2 with Zicsr, `o_trap` without Zicsr) |
| Zicsr | `has_zicsr` | `false` | No CSRs and no traps; the core signals the exception on `o_trap` |
| Zifencei | `has_zifencei` | `false` | `FENCE.I` is illegal (cause 2 with Zicsr, `o_trap` without Zicsr) |
| Zimop | `has_zimop` | `false` | The 40 encodings of `mop.r.n` and `mop.rr.n` are illegal (cause 2 with Zicsr, `o_trap` without Zicsr) |
| Zihintntl | `has_zihintntl` | `false` | The four `ntl.*` hints remain an `ADD` to `x0`, which is also a `nop` |
| Zihintpause | `has_zihintpause` | `false` | `pause` remains a `FENCE`, which is also a `nop` |
| Zicclsm | `has_zicclsm` | `true` | Every misaligned access traps |
| Zicond | `has_zicond` | `false` | `czero.eqz` and `czero.nez` are illegal (cause 2 with Zicsr, `o_trap` without Zicsr) |

A profile is a combination of those extensions, and two rules define the valid combinations: M and Zmmul never coexist, because M already includes the multiplication of Zmmul, and Zicntr and Zihpm imply Zicsr, because the counters are CSRs. A core with neither Zicsr nor Zicclsm is also valid: the misaligned access is only signalled on `o_trap`. The base is RV32I (`has_e` false) or RV32E (`has_e` true, see [ISA/E/description.md](docs/en/ISA/E/description.md)), and each base accepts all 60 combinations of extensions, which gives 120 profiles. The list of profiles comes from `profiles/matrix.yaml`, which does not expand Zicond; the `rv32im_zicond` profile turns it on in the GHDL build:

```bash
riscv-tools profiles --spec profiles/matrix.yaml                    # one name per line
riscv-tools profiles --spec profiles/matrix.yaml --format generics  # name and GHDL -g flags
make profile-matrix                                                        # elaborate each profile with its generics
```

When an extension is disabled by its generic, the corresponding instructions are illegal: with Zicsr they raise cause 2 of `mcause`, and without Zicsr they pulse `o_trap`, and in both cases they write no register and access no memory.

## 4. Verification and Execution

### 4.1. Local execution

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Core.git
cd Core
uv sync

make check          # VHDL syntax check of all sources in topological order
make profiles       # Independent compilation and elaboration of each profile in profiles/*.yaml
make test           # Run the full cocotb test suite (or make test TEST=ALU for a single target)
make paths          # Validate that all file paths listed in the manifests exist
make formal         # Run formal proofs (SymbiYosys) with the engine of FORMAL_ENGINE (bitwuzla by default)
```

### 4.2. Execution via Docker

The `ghcr.io/insper-riscv/ci-vhdl:latest` image published by [insper-riscv/Infra](https://github.com/insper-riscv/Infra) includes GHDL (LLVM backend), Yosys, SymbiYosys, the Yices, Bitwuzla and Boolector solvers, `uv`, Python 3.14, and cocotb 2.1.0 pre-installed:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/insper-riscv/ci-vhdl:latest \
  bash -c "uv sync && make check && make profiles && make test && make formal"
```

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](LICENSE).
