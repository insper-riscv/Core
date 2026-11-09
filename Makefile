SHELL := /bin/bash
GHDL  := ghdl
STD   := --std=08
WDIR  := build/ghdl

VHDL := $(shell find src -name '*.vhd' -not -path 'src/common/*' | sort) $(sort $(wildcard src/common/src/*.vhd))

.PHONY: check check-rv64 profiles profile-matrix configs test formal paths clean

# GHDL syntax check of every source, in dependency order (riscv-tools vhdl-sort).
check:
	@mkdir -p $(WDIR)
	@$(GHDL) -a $(STD) -Wno-library --work=work --workdir=$(WDIR) $$(riscv-tools vhdl-sort $(VHDL))
	@echo "VHDL syntax check passed"

# The same sources analyze with the rv64 variant of formal/configs.yaml (IS_64 true, 40-bit physical address): the
# types and the constants of the config_pkg carry the wider XLEN. The core does not run RV64 yet, so this stops at
# the analysis.
check-rv64: check configs
	@mkdir -p $(WDIR)/rv64
	@riscv-tools vhdl-sort $(VHDL) | tr ' ' '\n' | sed 's#^src/common/src/config_pkg.vhd$$#build/configs/rv64/config_pkg.vhd#' > $(WDIR)/rv64.order
	@$(GHDL) -a $(STD) -Wno-library --work=work --workdir=$(WDIR)/rv64 $$(cat $(WDIR)/rv64.order)
	@echo "RV64 analysis passed"

# Each profile builds on its own: analyze exactly its sources (profiles/<p>.yaml, a flat `- path` list), with the
# config_pkg of the profile (its `config:` constants, written by formal/config_variant.sh in the place of the default
# package of src/common), and elaborate the top with the generics the profile still has (`generics:`, the
# implementation sizes of the Zihpm). rv32i has no extension enabled and the last profile has every extension
# enabled. Every profile analyzes the same extension units, because core instantiates them directly, and the
# disabled ones leave the elaboration. GHDL 6 takes the generic at run time, so each profile is elaborated and
# run for 1 ns.
profiles: profile-matrix check-rv64
	@for p in rv32i rv32i_zmmul rv32im rv32im_zicsr rv32im_zicsr_irq rv32im_zicond rv32im_zicsr_zifencei rv32im_zicclsm_zicntr_zifencei rv32im_zicclsm_zicntr_zihpm_zifencei rv32im_zicclsm_zicntr_zihpm_zifencei_reduced rv32im_zimop; do \
	  srcs=$$(sed -n 's/^  - //p' profiles/$$p.yaml | grep '\.vhd$$'); \
	  sets=$$(sed -n 's/^config: {\(.*\)}/\1/p' profiles/$$p.yaml | tr ',' '\n' | sed 's/ *\([A-Za-z_0-9]*\): *\(.*\)/\1=\2/' | tr '\n' ' '); \
	  gens=$$(sed -n 's/^generics: {\(.*\)}/\1/p' profiles/$$p.yaml | tr ',' '\n' | sed 's/ *\([a-zA-Z_]*\): *\(.*\)/-g\1=\2/' | tr '\n' ' '); \
	  bash formal/build_profile.sh $$p $(WDIR)/$$p "$$sets" "$$gens" $$srcs || exit 1; \
	done

# Every profile of profiles/matrix.yaml (riscv-tools profiles) builds with its constants: each one analyzes the
# sources of `check` (their order) with its own config_pkg and elaborates the core, in parallel.
profile-matrix: check
	@riscv-tools vhdl-sort $(VHDL) | tr ' ' '\n' > $(WDIR)/order.txt
	@riscv-tools profiles --spec profiles/matrix.yaml --format generics | \
	  sed -e 's/-ghas_e=/IS_BASE_E=/' -e 's/ -ghas_\([a-z0-9]*\)=/ HAS_\U\1=/g' | \
	  QUIET=1 xargs -P $$(nproc) -L 1 bash -c 'bash formal/build_profile.sh matrix_$$0 $(WDIR)/matrix/$$0 "$$*" "" $$(cat $(WDIR)/order.txt) || exit 255'
	@echo "matrix: $$(riscv-tools profiles --spec profiles/matrix.yaml --format names | wc -l) profiles build"

# Formal proofs of the CSR bank, the trap unit, the counters and the fusion record, with their mutants
# (SymbiYosys, Yosys and one engine of the CI image: FORMAL_ENGINE is yices, bitwuzla, boolector or abc-bmc3);
# under a minute with bitwuzla. The result of the run is build/formal/result-<engine>.tsv.
FORMAL_ENGINE ?= bitwuzla
formal:
	FORMAL_ENGINE=$(FORMAL_ENGINE) bash formal/run.sh

# One config_pkg for each variant of formal/configs.yaml, in build/configs/<variant>/config_pkg.vhd, which the
# entries of tests/python/tests.json list in the place of the default package of src/common.
CONFIGS := $(shell sed -n 's/^\([a-z_0-9]*\):.*/\1/p' formal/configs.yaml)
configs:
	@for c in $(CONFIGS); do bash formal/config_variant.sh $$c build/configs/$$c/config_pkg.vhd || exit 1; done

# Per-entity cocotb tests; `make test TEST=ALU` for one entry of tests/python/tests.json.
test: configs
	uv run python tests/python/runner.py $(TEST)

# Every path the configuration lists exists, and the tree has the shape the Capstone defines (riscv-tools check-tree).
paths: configs
	riscv-tools --root . check-paths --manifest paths.yaml
	riscv-tools --root . check-tree --kind core

clean:
	rm -rf build
	find . -type f \( -name '*.vcd' -o -name '*.ghw' \) -print -delete
