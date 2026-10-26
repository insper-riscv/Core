# Core

🌐 [Português](README.md) · [English](README.en.md)

RISC-V RV32 processor in VHDL-2008 organized as an in-order 5-stage pipeline (IF, ID, EX, MEM, and WB), modularized by ISA extension (`I`, `M`, `Zicsr`, and `Zifencei`) under a single top-level entity (`core`), accompanied by per-entity unit tests via cocotb/GHDL and formal verification via SymbiYosys.

## 1. Documentation

- [AUTHORS.en.md](AUTHORS.en.md): authors with commits in the repository, with name and GitHub account.
- [CONTRIBUTING.en.md](CONTRIBUTING.en.md): mandatory contribution rules, VHDL-2008 standard (`--std=08`), naming conventions, `i_`/`o_` port prefixes, file headers, docstrings, and documentation rules.
- [README.md](docs/en/README.md): 32-bit RISC-V instruction formats, immediate generation table, and incremental datapath progression for the 37 base RV32I instructions.
- [ARCHITECTURE.md](docs/en/ARCHITECTURE.md): 5-stage pipeline microarchitecture, per-stage responsibilities, forwarding paths, load-use hazard detection, stall, flush, and support for the `M`, `Zicsr`, and `Zifencei` extensions.
- [PIPELINE_ARCHITECTURE_GUIDE.md](docs/en/PIPELINE_ARCHITECTURE_GUIDE.md): detailed reference of inter-stage interconnect signals, synchronous barriers (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`), stall and flush equations, and branch resolution.
- [DECODER.md](docs/en/DECODER.md): specification of the 21-bit RV32I base control word, dedicated decoding for `RV32M`, `Zicsr`, and `Zifencei`, register-file writeback selection, and illegal-instruction detection.
- [contracts/01-contrato-de-extensao.md](docs/en/contracts/01-contrato-de-extensao.md): extension directory contract, profile manifests (`profiles/*.yaml`), and single integration point for new extensions in the top-level entity.
- [contracts/02-barramento-e-memoria.md](docs/en/contracts/02-barramento-e-memoria.md): instruction and data bus protocol (byte addressing, byte enables, wait handshake for variable-latency memory, and instruction cache).
- [bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md](docs/en/bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md): mathematical analysis of the partial remainder range in non-restoring division and the use of 34 internal bits for unsigned divisors above $2^{31}$.
- [bugs/FLUSH_COM_PIPELINE_PARADO.md](docs/en/bugs/FLUSH_COM_PIPELINE_PARADO.md): analysis of the interaction between branch redirection in EX and global pipeline stall caused by memory wait in MEM.
- [bugs/LOAD_EM_WB_DURANTE_STALL.md](docs/en/bugs/LOAD_EM_WB_DURANTE_STALL.md): analysis of a load held in WB that was overwritten by the next load while the M unit stalls the pipeline.

## 2. Repository Structure

| Path | Contents |
| :--- | :--- |
| `common/` | Blocks shared across all profiles, including type and constant packages, inter-stage barrier registers, base control unit, register file, forwarding and hazard units, PC generator, and parameterized primitives |
| `I/` | Base integer extension RV32I, comprising the ALU, immediate extender, memory read extender, and store alignment manager |
| `M/` | Integer multiplication and division extension RV32M, containing a dedicated decoder, sequential radix-2 Booth multiplier, 34-bit non-restoring divider, and integration unit |
| `Zicsr/` | Machine-mode Control and Status Registers (CSRs) extension and synchronous exception and trap-return (`MRET`) detection unit |
| `Zifencei/` | Instruction-memory synchronization extension (`FENCE.I`), with optional write-back data-cache flush handshake support |
| `core/` | Entities for the 5 pipeline stages (`stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb`) and the processor structural top level (`core`) |
| `profiles/` | Source and generic manifests for each supported profile (`rv32i.yaml`, `rv32im.yaml`, `rv32im_zicsr.yaml`, `rv32im_zicsr_zifencei.yaml`) in dependency order |
| `formal/` | SystemVerilog properties (`csr_file_props.sv`, `trap_unit_props.sv`), `.sby` configurations, and formal verification script via GHDL + Yosys + SymbiYosys |
| `tests/python/` | Per-entity and top-level integration unit tests in cocotb/GHDL ([documentation](tests/python/README.en.md)) |
| `tests/FPGA/entities/` | Quartus project for on-board validation of the register file ([documentation](tests/FPGA/entities/bancoRegistradores/README.en.md)) |

## 3. ISA Profiles

The structural top level `core` takes four boolean generics that enable or disable each extension at elaboration time:

| Profile (`profiles/`) | Active extensions | Generics configured on top level `core` |
| :--- | :--- | :--- |
| `rv32i` | RV32I | `has_m: false, has_zicsr: false, has_zifencei: false, has_dcache_Wb: false` |
| `rv32im` | RV32I + M | `has_m: true, has_zicsr: false, has_zifencei: false, has_dcache_Wb: false` |
| `rv32im_zicsr` | RV32I + M + Zicsr | `has_m: true, has_zicsr: true, has_zifencei: false, has_dcache_Wb: false` |
| `rv32im_zicsr_zifencei` | RV32I + M + Zicsr + Zifencei | `has_m: true, has_zicsr: true, has_zifencei: true, has_dcache_Wb: false` |

When an extension is disabled by its generic, the corresponding instructions behave as `NOP` (no register write, no memory access, and no pipeline stall).

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
bash formal/run.sh  # Run formal proofs (SymbiYosys + Z3) for csr_file and trap_unit
```

### 4.2. Execution via Docker

The `ghcr.io/insper-riscv/ci-vhdl:latest` image published by [insper-riscv/Infra](https://github.com/insper-riscv/Infra) includes GHDL (LLVM backend), Yosys, SymbiYosys, Z3, `uv`, Python 3.14, and cocotb 2.1.0 pre-installed:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/insper-riscv/ci-vhdl:latest \
  bash -c "uv sync && make check && make profiles && make test && bash formal/run.sh"
```

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](LICENSE).
