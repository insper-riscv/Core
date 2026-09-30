# `tests/python`: per-entity VHDL unit tests (cocotb + GHDL)

Cocotb testbenches that exercise individual VHDL entities of the Core
(`ALU`, `RegFile`, the control, hazard and forwarding units, the extenders,
the store manager, the bubble mux, the instruction decoder) directly, one file
per entity. They drive the entity's ports straight from Python, without
`riscv-tools`' compiler or simulation flow. Tests that need the simulation
memories (whole-core instruction tests) live in the
[Tests](https://github.com/insper-riscv/Tests) repository.

## Structure

```
tests/python/
├── runner.py                    # catalog loader + cocotb/GHDL driver
├── tests.json                   # catalog: name -> {toplevel, sources, test_module, ...}
├── unittests/
│   ├── common/                  # entities of common/ (one file per entity) + data/ (fixtures, e.g. riscv_opcodes.csv)
│   ├── I/                       # entities of I/
│   └── M/                       # entities of M/
└── sim_build/                   # generated: <group>/<name>/{waves.ghw, ...} per test
```

## Running

```bash
make test                # every entry in tests.json (skips "skip": true ones)
make test TEST=ALU       # one entry, by its tests.json key
```

`SIM` picks the simulator (defaults to `ghdl`).

## The catalog (`tests.json`)

Each entry is a test name mapping to:

| Field | Meaning |
| :--- | :--- |
| `toplevel` | the VHDL entity under test |
| `sources` | its source files, relative to the root of this repository, in dependency order |
| `test_module` | the Python module with the cocotb tests |
| `skip` | optional: `true` leaves the entry out of a full run |
| `parameters` | optional: generics passed to the simulator |

A new entity test is a file in `unittests/<common|I|M>/`, next to the folder of the
entity's source, and an entry here.
