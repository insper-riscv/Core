SHELL := /bin/bash
GHDL  := ghdl
STD   := --std=08
WDIR  := build/ghdl

VHDL := $(shell find common I M Zicsr Zifencei cores -name '*.vhd' | sort)

.PHONY: check profiles test paths clean

# GHDL syntax check of every source, in dependency order (riscv-tools vhdl-sort).
check:
	@mkdir -p $(WDIR)
	@$(GHDL) -a $(STD) --work=work --workdir=$(WDIR) $$(uv run riscv-tools vhdl-sort $(VHDL))
	@echo "VHDL syntax check passed"

# Each profile builds on its own: analyze exactly its sources (profiles/<p>.yaml,
# a flat `- path` list) and elaborate the top with the profile's generic. rv32i
# has no M/ files, which proves the core builds without them. GHDL 6 takes the
# generic at run time, so each profile is elaborated and run for 1 ns.
profiles:
	@for p in rv32i rv32im rv32im_zicsr rv32im_zicsr_zifencei; do \
	  dir=$(WDIR)/$$p; rm -rf $$dir; mkdir -p $$dir; \
	  srcs=$$(sed -n 's/^  - //p' profiles/$$p.yaml | grep '\.vhd$$'); \
	  gens=$$(sed -n 's/^generics: {\(.*\)}/\1/p' profiles/$$p.yaml | tr ',' '\n' | sed 's/ *\([A-Z_]*\): *\(.*\)/-g\1=\2/' | tr '\n' ' '); \
	  $(GHDL) -a $(STD) --workdir=$$dir $$srcs && \
	  $(GHDL) --elab-run $(STD) --workdir=$$dir rv32im_pipeline_core $$gens --stop-time=1ns >/dev/null 2>&1 \
	  && echo "profile $$p builds ($$gens)" || { echo "profile $$p FAILED"; exit 1; }; \
	done

# Per-entity cocotb tests; `make test TEST=ALU` for one entry of tests/python/tests.json.
test:
	uv run python tests/python/runner.py $(TEST)

# Every path the configuration lists exists.
paths:
	uv run riscv-tools --root . check-paths --manifest paths.yaml

clean:
	rm -rf build
	find . -type f \( -name '*.vcd' -o -name '*.ghw' \) -print -delete
