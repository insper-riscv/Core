# Core

The RV32 pipeline core in VHDL (5 stages: IF, ID, EX, MEM, WB), organized by
ISA extension, with per-entity cocotb tests. One job: the processor. Memories,
peripherals, the top levels that wire them and the test programs live in other
repositories of [insper-riscv](https://github.com/insper-riscv).

## Layout

| Path | What |
| :--- | :--- |
| `common/` | what every profile shares: pipeline registers, forwarding and hazard units, bubble mux, PC, register file, instruction decoder, control unit, types and constants, generic blocks |
| `I/` | the base integer extension: ALU, immediate and load/store extenders, store manager |
| `M/` | multiply/divide: `decoderM`, `multdiv`, `mult`, `div`, `divu`, the Booth multiplier and the non-restoring divider |
| `cores/` | the top that instantiates the extensions of a profile (`rv32im_pipeline_core`) |
| `profiles/` | the sources of each supported profile, in dependency order (`rv32im.yaml`) |
| `tests/python/` | per-entity cocotb tests and the catalog (`tests.json`) that drives them |
| `tests/FPGA/entities/` | a Quartus project that exercises the register file on a board |
| `docs/` | pipeline and decoder documentation; `docs/contracts/` holds the extension contract and the bus and memory interface |

Zifencei and Zicsr will get their own folders when they are implemented.

## Use

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Core.git
cd Core
uv sync
make check   # GHDL syntax check of every source, in dependency order
make test    # per-entity cocotb tests (TEST=ALU for one)
make paths   # every path the configuration lists exists
```

The tools (GHDL, uv) come from the `infra-toolchain` image of
[Infra](https://github.com/insper-riscv/Infra); CI runs there.

## Where this came from

The files moved here from `insper-riscv/RV32` (`src/`, `docs/`,
`tests/FPGA/entities`) and from `insper-riscv/Tests` (`tests/python`), with
their history and authorship (`git filter-repo`). The pre-move state is the tag
`pre-refactor` in each of those repositories.

## License

Apache License 2.0, see [LICENSE](LICENSE).
