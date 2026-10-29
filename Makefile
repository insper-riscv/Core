SHELL := /bin/bash
GHDL  := ghdl
STD   := --std=08
WDIR  := build/ghdl

VHDL := $(shell find common I M Zicsr Zicntr Zifencei core -name '*.vhd' | sort) $(sort $(wildcard Common-Components/src/*.vhd))

.PHONY: check profiles profile-matrix test paths clean

# GHDL syntax check of every source, in dependency order (riscv-tools vhdl-sort).
check:
	@mkdir -p $(WDIR)
	@$(GHDL) -a $(STD) -Wno-library --work=work --workdir=$(WDIR) $$(uv run riscv-tools vhdl-sort $(VHDL))
	@echo "VHDL syntax check passed"

# Each profile builds on its own: analyze exactly its sources (profiles/<p>.yaml,
# a flat `- path` list) and elaborate the top with the profile's generic. rv32i
# has no M/ files, which proves the core builds without them. A last check shows that the
# forbidden combination (no Zicsr and no Zicclsm) does not elaborate. GHDL 6 takes the
# generic at run time, so each profile is elaborated and run for 1 ns.
profiles: profile-matrix
	@for p in rv32i rv32i_zmmul rv32im rv32im_zicsr rv32im_zicsr_zifencei; do \
	  dir=$(WDIR)/$$p; rm -rf $$dir; mkdir -p $$dir; \
	  srcs=$$(sed -n 's/^  - //p' profiles/$$p.yaml | grep '\.vhd$$'); \
	  gens=$$(sed -n 's/^generics: {\(.*\)}/\1/p' profiles/$$p.yaml | tr ',' '\n' | sed 's/ *\([a-zA-Z_]*\): *\(.*\)/-g\1=\2/' | tr '\n' ' '); \
	  $(GHDL) -a $(STD) --workdir=$$dir $$srcs && \
	  $(GHDL) --elab-run $(STD) --workdir=$$dir -o $$dir/core core $$gens --stop-time=1ns >/dev/null 2>&1 \
	  && echo "profile $$p builds ($$gens)" || { echo "profile $$p FAILED"; exit 1; }; \
	done
	@dir=$(WDIR)/rv32i; \
	if $(GHDL) --elab-run $(STD) --workdir=$$dir -o $$dir/core core -ghas_zicclsm=false --stop-time=1ns >/dev/null 2>&1; \
	then echo "profile without Zicsr and without Zicclsm was accepted, it must be rejected"; exit 1; \
	else echo "profile without Zicsr and without Zicclsm is rejected, as it must"; fi

# Every profile of profiles/matrix.yaml (riscv-tools profiles) elaborates with its generics, on the
# sources `check` analyzed.
profile-matrix: check
	@uv run riscv-tools profiles --spec profiles/matrix.yaml --format generics | while read -r name gens; do \
	  $(GHDL) --elab-run $(STD) --workdir=$(WDIR) -o $(WDIR)/matrix core $$gens --stop-time=1ns >/dev/null 2>&1 \
	  && echo "matrix $$name builds" || { echo "matrix $$name FAILED ($$gens)"; exit 1; }; \
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
