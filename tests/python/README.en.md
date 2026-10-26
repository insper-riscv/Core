# `tests/python`: Per-Entity Unit Tests (Cocotb + GHDL)

🌐 [Português](README.md) · [English](README.en.md)

Python (cocotb) testbench suite that individually exercises the processor's VHDL entities (`alu`, `reg_file`, `control_unit`, `hazard_detection_unit`, `forwarding_unit`, `bubble_mux`, `extender_imm`, `extender_ram`, `store_manager`, `m_decode`, `non_restoring_divider_rv32`, `csr_decode`, `csr_file`, `trap_unit`, and the top level `cpu`), driving their ports directly from the GHDL simulator.

## 1. Directory Structure

```
tests/python/
├── runner.py                    # Catalog loader and cocotb/GHDL runner
├── tests.json                   # Target catalog: name -> {toplevel, sources, test_module, parameters}
├── unittests/
│   ├── common/                  # Tests for common/ entities and reference table (data/riscv_opcodes.csv)
│   ├── I/                       # Tests for base I/ extension entities
│   ├── M/                       # Tests for the M/ extension decoder and divider
│   ├── Zicsr/                   # Tests for csr_decode, csr_file, and trap_unit
│   └── cores/                   # Top-level cpu integration tests (SDRAM stalls, I-cache, and FENCE.I)
└── sim_build/                   # Per-simulation build artifacts (<group>/<name>/waves.ghw)
```

## 2. Execution

```bash
make test                # Run all active entries in tests.json
make test TEST=ALU       # Run a single target by its catalog name
```

The `SIM` environment variable selects the simulator (defaults to `ghdl`).

## 3. Test Catalog (`tests.json`)

Each key in `tests/python/tests.json` defines a test target with the following fields:

| Field | Meaning |
| :--- | :--- |
| `toplevel` | Name of the VHDL entity under test (for example, `alu`, `reg_file`, `cpu`) |
| `sources` | List of required VHDL files, relative to the repository root and in compilation dependency order |
| `test_module` | Python module containing the `@cocotb.test()` coroutines |
| `parameters` | Optional dictionary of generics passed to the simulator at elaboration (for example, `{"has_m": false, "has_zifencei": true}`) |
| `build_args` / `test_args` | Additional arguments forwarded to GHDL (for example, `["--std=08"]`) |
| `skip` | Optional boolean; when `true`, skips the target during an unfiltered full run |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../LICENSE).
