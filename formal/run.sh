#!/usr/bin/env bash
# Formal verification of the CSR bank, the trap unit, the counters, the fusion record, the Zimop decoder and Zicond with SymbiYosys. Needs
# ghdl, yosys, sby and the engine chosen by FORMAL_ENGINE (all in the ci-vhdl image). Run from the root of the
# repository:  FORMAL_ENGINE=bitwuzla bash formal/run.sh
#
# FORMAL_ENGINE is one of yices, bitwuzla (the default), boolector and abc-bmc3. The first three are SMT solvers
# of the smtbmc engine; abc-bmc3 is the bounded model checker of ABC, which has no induction and no cover, so it
# skips those proofs. FORMAL_TIMEOUT (seconds, 900 by default) bounds each proof.
#
# CONFIG_FILE, when set, is a config_pkg that takes the place of src/common/src/config_pkg.vhd in the source list of
# the proof that follows it (the variants of formal/configs.yaml, written by formal/config_variant.sh). The units
# that the proofs share with the other repositories (counter64, for one) are proven in their own repository.
#
# Besides the report, the run writes build/formal/result-<engine>.tsv, one line per proof with the columns
# id, wanted (pass or fail), verdict (pass, fail, error or skip), sby exit code, milliseconds and the label, which
# formal/aggregate.sh joins across engines.
#
# A warning is an error. Every ghdl and sby/yosys output of the run (the proofs and the mutants) goes through
# scan_warnings (formal/warnings.sh); any line with the word "warning" makes the run fail, naming the file and
# the line. The flags that hide warnings (-Wno-*) are not used: the cause of a warning is fixed in the VHDL or in
# the proofs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/formal"
rm -rf "$out"; mkdir -p "$out"; cd "$out"

engine="${FORMAL_ENGINE:-bitwuzla}"
case "$engine" in
  yices|bitwuzla|boolector|abc-bmc3) ;;
  *) echo "FORMAL_ENGINE must be yices, bitwuzla, boolector or abc-bmc3, not '$engine'" >&2; exit 2 ;;
esac
timeout_s="${FORMAL_TIMEOUT:-900}"
results="$out/result-$engine.tsv"; : > "$results"

fail=0
warnings="$out/warnings.txt"; : > "$warnings"
# shellcheck source=formal/warnings.sh
source "$root/formal/warnings.sh"

# expect <label> <wanted: PASS|FAIL> <result: PASS|FAIL|SKIP|ERROR ...>. An ERROR (the tool did not reach a verdict)
# never matches, not even a wanted FAIL; a SKIP is a proof this engine does not do and is not a failure. The id,
# the exit code and the time of the proof come from the files prove left for its tag.
expect() {
  local tag verdict rc ms
  tag="$(cat "$out/.last")"
  IFS=$'\t' read -r verdict rc ms < "$out/$tag.res"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$tag" "${2,,}" "$verdict" "$rc" "$ms" "$1" >> "$results"
  case "$3" in
    SKIP*) printf '  skip  %-62s %s\n' "$1" "${3#SKIP }" ;;
    ERROR*) printf '  ERROR %-62s %s\n' "$1" "${3#ERROR }"; fail=1 ;;
    "$2") printf '  ok    %-62s %s (%s ms)\n' "$1" "$3" "$ms" ;;
    *) printf '  WRONG %-62s wanted %s, got %s\n' "$1" "$2" "$3"; fail=1 ;;
  esac
}

# resolve_gens <name> [ghdl generics]: separates the constants of the config_pkg (-ghas_*, -gstrict_periph and -gbase_e, the names the
# core had as generics) from the generics that remain. CFG_FILE gets the config_pkg of the
# unit (CONFIG_FILE, or the default one, with those constants set, written in the output folder) and GEN_FLAGS the flags
# for GHDL.
resolve_gens() {
  local name="$1" flag key sets=""
  shift
  GEN_FLAGS=""
  for flag in "$@"; do
    key="${flag#-g}"; key="${key%%=*}"
    case "${key,,}" in
      has_e|base_e) sets="$sets IS_BASE_E=${flag#*=}" ;;
      has_*|strict_periph) sets="$sets ${key^^}=${flag#*=}" ;;
      *) GEN_FLAGS="$GEN_FLAGS $flag" ;;
    esac
  done
  CFG_FILE="${CONFIG_FILE:-$root/src/common/src/config_pkg.vhd}"
  if [ -n "$sets" ]; then
    CONFIG_BASE="$CFG_FILE" bash "$root/formal/config_variant.sh" --set "$sets" "$out/cfg_$name.vhd" >&2
    CFG_FILE="$out/cfg_$name.vhd"
  fi
}

# netlist <vhdl> <entity> <name> [ghdl generics]: the Verilog netlist GHDL synthesizes for the entity, with the
# bank of event counters of BANK_FILE (the real one by default). The mutant takes the place of the original unit in
# the analysis order: REPLACES names the file the mutant stands for, and the file under proof ($1) is analyzed in
# its place, so that no entity is defined in two files. Without REPLACES, $1 comes last.
netlist() {
  local work="$out/work_$3" replaces="${REPLACES:-}" log="$out/$3.ghdl.log" file replaced=0 files=()
  mkdir -p "$work"; : > "$log"
  resolve_gens "$3" ${@:4}
  for file in \
    "$root/src/common/src/utils_pkg.vhd" \
    "$CFG_FILE" \
    "$root/src/shared/pipeline_types.vhd" \
    "$root/src/shared/byte_mask_consts.vhd" \
    "$root/src/shared/opcode_consts.vhd" \
    "$root/src/shared/funct3_consts.vhd" \
    "$root/src/shared/funct7_consts.vhd" \
    "$root/src/shared/alu_consts.vhd" \
    "$root/src/Zimop/zimop_consts.vhd" \
    "$root/src/Zihintntl/zihintntl_consts.vhd" \
    "$root/src/Zihintpause/zihintpause_consts.vhd" \
    "$root/src/common/src/flip_flop.vhd" \
    "$root/src/common/src/generic_register.vhd" \
    "$root/src/shared/mem_map_consts.vhd" \
    "$root/src/shared/word_consts.vhd" \
    "$root/src/Zicond/zicond_consts.vhd" \
    "$root/src/Zicsr/trap_consts.vhd" \
    "$root/src/Zicsr/csr_addr_consts.vhd" \
    "$root/src/Zicsr/csr_event_consts.vhd" \
    "$root/src/Zicsr/csr_value_consts.vhd" \
    "$root/src/Zicsr/irq_consts.vhd" \
    "$root/src/common/src/mux_tree.vhd" \
    "$root/src/common/src/counter64.vhd" \
    "$root/src/Zicntr/tick_divider.vhd" \
    "${BANK_FILE:-$root/src/Zihpm/hpm_counter_bank.vhd}"; do
    if [ -n "$replaces" ] && [ "$file" = "$replaces" ]; then file="$1"; replaced=1; fi
    files+=("$file")
  done
  [ "$replaced" = 1 ] || files+=("$1")
  for file in "${files[@]}"; do
    ghdl -a --std=08 --workdir="$work" "$file" 2>> "$log" || { cat "$log" >&2; return 1; }
  done
  ghdl --synth --std=08 --workdir="$work" --out=verilog $GEN_FLAGS "$2" > "$3.v" 2>> "$log" || { cat "$log" >&2; return 1; }
  scan_warnings "$log"
}

# config_variant <name>: the config_pkg of the variant <name> of formal/configs.yaml (the default package of
# src/common with the constants of the variant), written in the output folder; the path is the CONFIG_FILE that
# puts it in the place of the default one in the source list of netlist and netlist_tree.
config_variant() {
  bash "$root/formal/config_variant.sh" "$1" "$out/config_$1.vhd" >&2 && echo "$out/config_$1.vhd"
}

# netlist_tree <entity> <name> [ghdl generics]: the Verilog netlist of an entity that needs the whole source tree
# (stage_ex), with every source of the repository analyzed in the order riscv-tools vhdl-sort gives. A mutant
# takes the place of the original file: TREE_REPLACES names the file and TREE_COPY is the mutant.
netlist_tree() {
  local work="$out/work_$2" log="$out/$2.ghdl.log" file
  mkdir -p "$work"; : > "$log"
  resolve_gens "$2" ${@:3}
  while read -r file; do
    if [ -n "${TREE_REPLACES:-}" ] && [ "$file" = "$TREE_REPLACES" ]; then file="$TREE_COPY"; else file="$root/$file"; fi
    if [ "$file" = "$root/src/common/src/config_pkg.vhd" ]; then file="$CFG_FILE"; fi
    ghdl -a --std=08 --workdir="$work" "$file" 2>> "$log" || { cat "$log" >&2; return 1; }
  done < <(cd "$root" && riscv-tools vhdl-sort $(find src -name '*.vhd' -not -path 'src/common/*' | sort) $(ls src/common/src/*.vhd | sort) | tr ' ' '\n')
  ghdl --synth --std=08 --workdir="$work" --out=verilog $GEN_FLAGS "$1" > "$2.v" 2>> "$log" || { cat "$log" >&2; return 1; }
  scan_warnings "$log"
}

# Probes: a property that keeps a model of a register outside the unit cannot be proven by induction on its own,
# because the induction starts from any state of the unit and the model is free. The fix is an invariant that
# says the model is the register, so prove connects (PROBES) wires of props to nets of the flattened netlist
# (dut.<net>) with the yosys command connect. For abc-bmc3, the flatten and the opt_clean -purge drop the aliases
# of the clock (dut.i_clk and the like): with them the AIGER writer takes an alias for the representative of the
# clock net, which is not an input, and warns that the clock is an undriven bit.
#
# prove <netlist> <props> <mode: prove|bmc|cover> <depth> <defines> <tag>  ->  PASS, FAIL, SKIP or ERROR
# PASS is sby exit code 0, FAIL is 2 (a counterexample or a goal that cannot be covered) and any other code
# (4 unknown, 8 timeout, 16 error, 124 the FORMAL_TIMEOUT) is ERROR: the tool did not reach a verdict. The
# abc-bmc3 engine only checks bounded properties of designs with registers, so it answers SKIP for a proof by
# induction, for a cover and for a combinational design.
# The verdict, the exit code and the milliseconds go to <tag>.res, and the tag to .last, for expect.
prove() {
  echo "$6" > "$out/.last"
  local engine_lines script_lines options_lines="" probe_lines="" probe rc=0 verdict began ended
  # PROBES is a list of <wire of props>=<net of the netlist>: the wire is connected to the register of the unit, so that
  # a property can state the invariant that ties the model to the state of the design (see "probes" above).
  for probe in ${PROBES:-}; do probe_lines+=$'\n'"connect -set ${probe%%=*} ${probe#*=}"; done
  [ -z "$probe_lines" ] || probe_lines=$'hierarchy -top props\nproc\nflatten\ncd props'"$probe_lines"$'\ncd'
  case "$engine" in
    abc-bmc3)
      if [ "$3" != bmc ]; then
        printf 'SKIP\t-\t0\n' > "$6.res"; echo "SKIP abc-bmc3 has no $3"; return
      fi
      engine_lines="abc bmc3"
      options_lines="aigsmt none"
      script_lines=$'flatten\nsetundef -undriven -anyseq\nopt_clean -purge\ntechmap\nopt -fast\nsetundef -anyseq' ;;
    *) engine_lines="smtbmc $engine"; script_lines="" ;;
  esac
  cat > "$6.sby" <<EOS
[options]
mode $3
depth $4
$options_lines
[engines]
$engine_lines
[script]
read_verilog -formal -sv $5 $1 $2
$probe_lines
prep -top props
$script_lines
[files]
$1
$2
EOS
  began=$(date +%s%N)
  timeout "$timeout_s" sby -f "$6.sby" > "$6.log" 2>&1 || rc=$?
  ended=$(date +%s%N)
  # ABC refuses a design without registers (the trap unit is combinational): that is a proof this engine does
  # not do, not a failure of the tool. Its warning "The network is combinational." comes with the refusal.
  if [ "$engine" = abc-bmc3 ] && [ "$rc" = 16 ] && grep -q 'Does not work for combinational networks' "$6.log"; then
    scan_warnings "$6.log" skipped
    printf 'skip\t%s\t0\n' "$rc" > "$6.res"; echo "SKIP abc-bmc3 does not work for a combinational design"; return
  fi
  case "$rc" in
    0) verdict=PASS ;;
    2) verdict=FAIL ;;
    *) verdict=ERROR ;;
  esac
  scan_warnings "$6.log"
  printf '%s\t%s\t%s\n' "${verdict,,}" "$rc" "$(( (ended - began) / 1000000 ))" > "$6.res"
  case "$verdict" in
    ERROR) echo "ERROR sby exited with code $rc, not a verdict (see $6.log)" ;;
    *) echo "$verdict" ;;
  esac
}

csr="$root/src/Zicsr/csr_file.vhd"; csr_props="$root/formal/csr_file_props.sv"
trap="$root/src/Zicsr/trap_unit.vhd"; trap_props="$root/formal/trap_unit_props.sv"

echo "csr_file"
netlist "$csr" csr_file csr
expect "fixed bits, quiet CSRs, write-then-read, trap, reset (induction)" PASS "$(prove csr.v "$csr_props" prove 6 ''                       csr_safety)"
expect "mstatus: a trap saves MIE, MRET restores it (induction)"          PASS "$(prove csr.v "$csr_props" prove 6 '-DMSTATUS_MODE'        csr_mstatus)"
expect "cover: a trap with MIE set and an MRET are reachable"             PASS "$(prove csr.v "$csr_props" cover 12 '-DCOVER -DMSTATUS_MODE' csr_cover_mstatus)"
expect "cover: an mtvec write and a trap together with a commit"          PASS "$(prove csr.v "$csr_props" cover 12 '-DCOVER'               csr_cover)"

echo "trap_unit"
netlist "$trap" trap_unit trap
expect "causes, mtval, MRET, ecall/ebreak/wfi, aligned accesses (induction)" PASS "$(prove trap.v "$trap_props" prove 2 ''        trap_safety)"
expect "cover: every cause and MRET are reachable"                           PASS "$(prove trap.v "$trap_props" cover 2 '-DCOVER' trap_cover)"
expect "Zicclsm: misaligned in the main memory runs, outside it traps (induction)" PASS "$(prove trap.v "$trap_props" prove 2 '-DZICCLSM_ON' trap_zicclsm_on)"
netlist "$trap" trap_unit trap_noea -gcheck_ea=false
expect "no address check: causes 4 and 6 never occur (induction)"             PASS "$(prove trap_noea.v "$trap_props" prove 2 '-DCHECK_EA_OFF' trap_noea_safety)"
netlist "$trap" trap_unit trap_off -gHAS_ZICCLSM=false
expect "no Zicclsm: every misaligned access traps (induction)"                PASS "$(prove trap_off.v "$trap_props" prove 2 '-DZICCLSM_OFF' trap_zicclsm_off)"
CONFIG_FILE="$(config_variant ext_flash)" netlist "$trap" trap_unit trap_ext
expect "sdram map: misaligned in the flash and the SDRAM runs, elsewhere traps (induction)" PASS "$(prove trap_ext.v "$trap_props" prove 2 '-DZICCLSM_ON -DEXT_FLASH' trap_zicclsm_ext)"

echo "trap_unit with an interrupt to take"
expect "the interrupt is taken on a valid, advancing instruction that is not FENCE.I, wins over every exception and MRET, carries its cause and mtval 0 (induction)" PASS "$(prove trap.v "$trap_props" prove 2 '-DIRQ' trap_irq)"
expect "cover: an interrupt over ecall, over MRET, over an illegal instruction, over a misaligned jump and over a load, and a deferred FENCE.I are reachable" PASS "$(prove trap.v "$trap_props" cover 2 '-DIRQ -DCOVER' trap_irq_cover)"

echo "trap_unit with access faults"
trap_af_props="$root/formal/trap_af_props.sv"
trap_af_gens="-ghas_access_faults=true"
netlist "$trap" trap_unit trap_af "$trap_af_gens"
expect "fetch fault is cause 1 with the PC and beats everything, a load or store the map refuses is cause 5 or 7 with the address, nothing else raises them (induction)" PASS "$(prove trap_af.v "$trap_af_props" prove 2 '' trap_af_safety)"
expect "cover: causes 1, 5 and 7, a fetch fault over an illegal instruction and a misaligned load fault are reachable" PASS "$(prove trap_af.v "$trap_af_props" cover 2 '-DCOVER' trap_af_cover)"

echo "reg_ex_mem validity flags on the window of the peripherals"
exmem="$root/src/shared/reg_ex_mem.vhd"; exmem_props="$root/formal/exmem_periph_props.sv"
exmem_gens="-ghas_access_faults=true -gperiph_slots=00001001"
CONFIG_FILE="$(config_variant faults_map)" netlist "$exmem" reg_ex_mem exmem "$exmem_gens"
expect "strict peripherals: a slot without a peripheral refuses read and write, the occupied slots, the RAM and the ROM follow the map, a bubble refuses nothing (bounded, 6 cycles)" PASS "$(prove exmem.v "$exmem_props" bmc 6 '' exmem_safety)"
expect "cover: an occupied slot, a refused slot, the RAM, a hole and a bubble are reachable" PASS "$(prove exmem.v "$exmem_props" cover 6 '-DCOVER' exmem_cover)"
CONFIG_FILE="$(config_variant faults_map)" netlist "$exmem" reg_ex_mem exmem_loose "$exmem_gens -gstrict_periph=false"
expect "STRICT_PERIPH false: every slot of the window accepts read and write (bounded, 6 cycles)" PASS "$(prove exmem_loose.v "$exmem_props" bmc 6 '-DLOOSE' exmem_loose_safety)"
expect "cover: with STRICT_PERIPH false a slot without a peripheral is accepted" PASS "$(prove exmem_loose.v "$exmem_props" cover 6 '-DLOOSE -DCOVER' exmem_loose_cover)"

echo "muldiv_fusion"
fus="$root/src/M/muldiv_fusion.vhd"; fus_props="$root/formal/muldiv_fusion_props.sv"
netlist "$fus" muldiv_fusion fus
# The record mirrors the units' last full result, so this proof is bounded from reset: the fusion is a hit only on the rule and shows the full result of the earlier execution.
expect "hit only on the same values, family and another operation; the record is the last full result (bounded, 10 cycles)" PASS "$(prove fus.v "$fus_props" bmc 10 '' fus_safety)"
expect "cover: a hit in each family and the near misses are reachable" PASS "$(prove fus.v "$fus_props" cover 10 '-DCOVER' fus_cover)"

echo "zimop_decode"
zim="$root/src/Zimop/zimop_decode.vhd"; zim_props="$root/formal/zimop_props.sv"
netlist "$zim" zimop_decode zim
expect "exactly the 32 mop.r.n and the 8 mop.rr.n are claimed, they write rd and carry a zero-result ALU operation (induction)" PASS "$(prove zim.v "$zim_props" prove 2 '' zim_safety)"
expect "cover: a mop.r, a mop.rr and an unclaimed SYSTEM instruction are reachable" PASS "$(prove zim.v "$zim_props" cover 2 '-DCOVER' zim_cover)"

echo "zihintntl_decode"
ntl="$root/src/Zihintntl/zihintntl_decode.vhd"; ntl_props="$root/formal/zihintntl_props.sv"
netlist "$ntl" zihintntl_decode ntl
expect "exactly the four ADD x0, x0, x2..x5 are claimed (induction)" PASS "$(prove ntl.v "$ntl_props" prove 2 '' ntl_safety)"
expect "cover: a hint, an ADD with another rs2 and an ADD with a nonzero rd are reachable" PASS "$(prove ntl.v "$ntl_props" cover 2 '-DCOVER' ntl_cover)"

echo "zihintpause_decode"
pau="$root/src/Zihintpause/zihintpause_decode.vhd"; pau_props="$root/formal/zihintpause_props.sv"
netlist "$pau" zihintpause_decode pau
expect "exactly the word 0x0100000F is claimed (induction)" PASS "$(prove pau.v "$pau_props" prove 2 '' pau_safety)"
expect "cover: pause and another FENCE are reachable" PASS "$(prove pau.v "$pau_props" cover 2 '-DCOVER' pau_cover)"

echo "csr_file with Zicntr"
netlist "$csr" csr_file csrc "-ghas_zicntr=true -gtick_cycles=3"
csr_cntr_props="$root/formal/csr_cntr_props.sv"
# The counters' own state is internal to the unit that counter64 already proves, so this proof is bounded from reset: it checks the wiring (addresses, halves, write path, legality).
expect "mcycle/minstret follow the 64-bit models, writes per half, read-only mirrors (bounded, 6 cycles)" PASS "$(prove csrc.v "$csr_cntr_props" bmc 6 ''           csrc_safety)"
expect "cover: a write at the carry point and a write with a retire are reachable"                PASS "$(prove csrc.v "$csr_cntr_props" cover 12 '-DCOVER' csrc_cover)"

echo "csr_file with Zihpm"
csr_hpm_props="$root/formal/csr_hpm_props.sv"
# The counters share the counter64 already proven, and the 29 indices share one structure, so a symbolic index
# stands for them all. The proofs are bounded from reset: they check the wiring (the five ranges, event
# selection, inhibit bits, width, write path, legality).
netlist "$csr" csr_file csrh29 "-ghas_zihpm=true -ghpm_counters=29 -ghpm_width=33"
expect "29 counters of 33 bits (the width is proven apart): every index exists, reads and writes follow the model, mirrors read-only (bounded, 4 cycles)" PASS "$(prove csrh29.v "$csr_hpm_props" bmc 4 '-DNHPM=29 -DWIDTH=33' csrh29_safety)"
netlist "$csr" csr_file csrh "-ghas_zihpm=true -ghpm_counters=4 -ghpm_width=64"
expect "4 counters: indices past them read zero and ignore writes (bounded, 6 cycles)" PASS "$(prove csrh.v "$csr_hpm_props" bmc 6 '-DNHPM=4' csrh_safety)"
expect "cover: a count at the carry point, an inhibited event, a write with a count and a write past the counters are reachable" PASS "$(prove csrh.v "$csr_hpm_props" cover 12 '-DNHPM=4 -DCOVER' csrh_cover)"
netlist "$csr" csr_file csrh2 "-ghas_zihpm=true -ghpm_counters=2 -ghpm_width=40 -ghas_zicntr=true -gtick_cycles=3"
expect "2 counters of 40 bits with Zicntr: mcycle/minstret own bits 0 and 2, the width truncates (bounded, 6 cycles)" PASS "$(prove csrh2.v "$csr_hpm_props" bmc 6 '-DNHPM=2 -DWIDTH=40 -DHAS_CNTR' csrh2_safety)"
netlist "$csr" csr_file csrh3 "-ghas_zihpm=true -ghpm_counters=5 -ghpm_width=20"
expect "5 counters of 20 bits: the low half truncates and the high half reads zero (bounded, 6 cycles)" PASS "$(prove csrh3.v "$csr_hpm_props" bmc 6 '-DNHPM=5 -DWIDTH=20' csrh3_safety)"
netlist "$csr" csr_file csrh0 "-ghas_zihpm=true -ghpm_counters=3 -ghpm_width=0"
expect "width 0: no real counter, all 29 indices read zero (bounded, 6 cycles)" PASS "$(prove csrh0.v "$csr_hpm_props" bmc 6 '-DNHPM=3 -DWIDTH=0' csrh0_safety)"

echo "csr_file with interrupts"
csr_irq_props="$root/formal/csr_irq_props.sv"
# The model keeps the mask bits of mie, MIE and MPIE of mstatus and mtvec, which are registers of the unit. The
# invariant that the model is the register uses probes (see "Probes" above), so the proofs are by induction.
irq_probes="pr_en=dut.irq_en_reg pr_mie=dut.mstatus_mie pr_mpie=dut.mstatus_mpie pr_mode=dut.mtvec_mode pr_mtvec=dut.mtvec_reg"
PROBES="$irq_probes"
netlist "$csr" csr_file csri "-ghas_interrupts=true"
expect "mip reads the three lines, mie keeps bits 3, 7 and 11, a write to mip changes nothing, pending is lines and mask, take needs MIE, the cause has the priority external, software, timer, mtvec keeps BASE and MODE (induction)" PASS "$(prove csri.v "$csr_irq_props" prove 4 '' csri_safety)"
expect "the same properties, bounded from reset (bounded, 6 cycles; the only form the abc-bmc3 engine answers)" PASS "$(prove csri.v "$csr_irq_props" bmc 6 '' csri_bounded)"
expect "cover: a pending timer alone, a mie write setting MTIE and a write to mip are reachable" PASS "$(prove csri.v "$csr_irq_props" cover 12 '-DCOVER' csri_cover)"
netlist "$csr" csr_file csrio "-ghas_interrupts=false"
expect "without the generic the lines are ignored: mip and mie read zero, writes change nothing, pending is 0 (induction)" PASS "$(prove csrio.v "$csr_irq_props" prove 4 '-DOFF' csrio_safety)"
PROBES=""

echo "csr_file with time_external"
csr_time_props="$root/formal/csr_time_props.sv"
time_gens="-ghas_zicntr=true -gtime_external=true"
netlist "$csr" csr_file csrt "$time_gens"
expect "time and timeh read the halves of the mtime port, a write to them is illegal and a read is not (bounded, 4 cycles)" PASS "$(prove csrt.v "$csr_time_props" bmc 4 '' csrt_safety)"
expect "cover: a read of timeh with a nonzero mtime and a write to time are reachable" PASS "$(prove csrt.v "$csr_time_props" cover 6 '-DCOVER' csrt_cover)"
echo "csr_file with Sscofpmf"
csr_ofp_props="$root/formal/csr_ofp_props.sv"
ofp_gens="-ghas_zihpm=true -ghpm_counters=2 -ghpm_width=3 -ghas_interrupts=true -ghas_sscofpmf=true"
netlist "$csr" csr_file csrof "$ofp_gens"
expect "OF, MINH, LCOFIP and LCOFIE follow the model: the overflow sets OF and, with OF clear, LCOFIP; the timer goes before LCOFI; a counter past the real ones reads zero (bounded, 10 cycles)" PASS "$(prove csrof.v "$csr_ofp_props" bmc 10 '-DNHPM=2 -DWIDTH=3' csrof_safety)"
expect "cover: an overflow with OF clear and with OF set, a pending LCOFI taken, both pending, OF and LCOFIP cleared by software, an event ignored because MINH is set are reachable" PASS "$(prove csrof.v "$csr_ofp_props" cover 14 '-DNHPM=2 -DWIDTH=3 -DCOVER' csrof_cover)"

echo "stage_ex with interrupts"
stage_props="$root/formal/stage_ex_irq_props.sv"
ex_gens="-ghas_zicsr=true -ghas_interrupts=true"
netlist_tree stage_ex stage_irq $ex_gens
expect "an interrupt aborts the instruction in EX: mepc is its address, mcause its cause and line, MIE 0 and MPIE 1, the next PC is BASE or the vector, an aborted CSR access changes nothing (induction)" PASS "$(prove stage_irq.v "$stage_props" prove 2 '' stage_irq_safety)"
expect "cover: the aborts of an ADDI and of CSR accesses to mscratch, mie and mtvec, and the vectored mode, are reachable" PASS "$(prove stage_irq.v "$stage_props" cover 14 '-DCOVER' stage_irq_cover)"

echo "zicond_unit"
zc="$root/src/Zicond/zicond_unit.vhd"; zc_props="$root/formal/zicond_props.sv"
netlist "$zc" zicond_unit zc
expect "czero.eqz and czero.nez give zero or rs1 by the condition of rs2, no other code is claimed (induction)" PASS "$(prove zc.v "$zc_props" prove 2 '' zc_safety)"
expect "cover: both instructions, both outcomes and an unclaimed code are reachable"                         PASS "$(prove zc.v "$zc_props" cover 2 '-DCOVER' zc_cover)"

echo "zicond_decode"
zd="$root/src/Zicond/zicond_decode.vhd"; zd_props="$root/formal/zicond_decode_props.sv"
netlist "$zd" zicond_decode zd
expect "exactly opcode 0110011, funct7 0000111 and funct3 101 or 111 are claimed, with their codes (induction)" PASS "$(prove zd.v "$zd_props" prove 2 '' zd_safety)"
expect "cover: both claims and the near misses are reachable"                                               PASS "$(prove zd.v "$zd_props" cover 2 '-DCOVER' zd_cover)"

echo "core: o_trap_take"
core_file="$root/src/core/core.vhd"; core_props="$root/formal/core_trap_take_props.sv"
# core_netlist <name> [ghdl generics]: the netlist of the whole core with Zicsr, on the sources of its profile, with
# CORE_FILE (a mutant) in the place of core.vhd when it is set.
core_netlist() {
  local work="$out/work_$1" log="$out/$1.ghdl.log" file name="$1"
  mkdir -p "$work"; : > "$log"
  resolve_gens "$1" ${@:2}
  while read -r file; do
    [ "$root/$file" = "$core_file" ] && [ -n "${CORE_FILE:-}" ] && file="$CORE_FILE" || file="$root/$file"
    [ "$file" = "$root/src/common/src/config_pkg.vhd" ] && file="$CFG_FILE"
    ghdl -a --std=08 --workdir="$work" "$file" 2>> "$log" || { cat "$log" >&2; return 1; }
  done < <(sed -n 's/^  - //p' "$root/profiles/rv32im_zicsr.yaml" | grep '\.vhd$')
  ghdl --synth --std=08 --workdir="$work" --out=verilog $GEN_FLAGS core > "$name.v" 2>> "$log" || { cat "$log" >&2; return 1; }
  scan_warnings "$log"
}
core_netlist core_take -ghas_zicsr=true
expect "Zicsr: o_trap stays low, a take retires nothing and never repeats in the next cycle (bounded, 10 cycles)" PASS "$(prove core_take.v "$core_props" bmc 10 '' core_take_safety)"
expect "cover: a take is reachable" PASS "$(prove core_take.v "$core_props" cover 12 '-DCOVER' core_take_cover)"
echo "alu"
alu="$root/src/I-E/alu.vhd"; alu_props="$root/formal/alu_props.sv"
netlist "$alu" alu alu
expect "the data result and the branch flag are the plain operators for every operation (equivalence)" PASS "$(prove alu.v "$alu_props" prove 2 '' alu_safety)"
expect "cover: the arithmetic shift, the sign-crossing comparisons, JALR and the branches are reachable" PASS "$(prove alu.v "$alu_props" cover 2 '-DCOVER' alu_cover)"

# Mutants of the VHDL: each defect must make a proof fail.
mutant() {  # <file> <props> <entity> <defines> <name> <sed expression> [ghdl generics] [bmc depth]
  local copy="$out/mut_$5.vhd"
  sed "$6" "$1" > "$copy"
  cmp -s "$1" "$copy" && { echo "mutant $5: the edit did not change the file"; exit 1; }
  REPLACES="$1" netlist "$copy" "$3" "mut_$5" ${7:-}
  expect "mutant $5 is caught" FAIL "$(prove "mut_$5.v" "$2" bmc "${8:-8}" "$4" "mut_$5")"
}
mutant "$csr"  "$csr_props"  csr_file  '-DMSTATUS_MODE' trap_keeps_mie  "s/mie_nxt <= '0'          when i_trap_take = '1'/mie_nxt <= mstatus_mie  when i_trap_take = '1'/"
mutant "$csr"  "$csr_props"  csr_file  '-DMSTATUS_MODE' mret_no_mpie    "s/'1'         when i_mret_take = '1'/'0'         when i_mret_take = '1'/"
mutant "$csr"  "$csr_props"  csr_file  ''               mepc_odd         "s/new_value(31 downto 2) \& BYTE_OFFSET_0;/new_value;/"
mutant "$csr"  "$csr_props"  csr_file  ''               trap_no_mcause   "s/mcause_nxt  <= i_trap_cause when i_trap_take = '1' else new_value;/mcause_nxt  <= mcause_reg   when i_trap_take = '1' else new_value;/"
mutant "$trap" "$trap_props" trap_unit  ''              load_halfword    "s/((i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU) and i_ea(0) = '1')/((i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU) and i_ea(1) = '1')/"
mutant "$trap" "$trap_props" trap_unit  ''              mret_any_imm     "s/is_mret   <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_MRET)/is_mret   <= '1' when (is_system = '1' and no_regs = '1')/"
mutant "$trap" "$trap_props" trap_unit  '-DZICCLSM_ON' crossing_any_region "s/ and same_region = '1'//"
mutant "$trap" "$trap_props" trap_unit  '-DZICCLSM_ON' in_word_any_region  "s/in_main_mem = '1' and i_ea(1 downto 0) = BYTE_OFFSET_1/i_ea(1 downto 0) = BYTE_OFFSET_1/"
mutant "$trap" "$trap_props" trap_unit  ''              illegal_ignored  "s/has_exc <= fetch_fault or cf_misal or any_illegal or/has_exc <= fetch_fault or cf_misal or/"
mutant "$trap" "$trap_props" trap_unit  ''              misaligned_over_illegal "s/CAUSE_ILLEGAL_INSTR when any_illegal = '1' else/CAUSE_MISALIGNED_PC when (i_cf_taken = '1' and not (i_cf_target(1 downto 0) = BYTE_OFFSET_0)) else CAUSE_ILLEGAL_INSTR when any_illegal = '1' else/"

mutant "$trap" "$trap_af_props" trap_unit  ''              af_fetch_below_illegal "s/CAUSE_FETCH_FAULT   when fetch_fault = '1' else/CAUSE_ILLEGAL_INSTR when any_illegal = '1' else CAUSE_FETCH_FAULT   when fetch_fault = '1' else/" "$trap_af_gens"
mutant "$trap" "$trap_af_props" trap_unit  ''              af_load_uses_write_flag "s/i_opcode = OPCODE_LOAD and i_ea_rd_ok = '0'/i_opcode = OPCODE_LOAD and i_ea_wr_ok = '0'/" "$trap_af_gens"
mutant "$trap" "$trap_af_props" trap_unit  ''              af_fault_before_misaligned "s/ and st_misal = '0') else '0';/) else '0';/;s/CAUSE_MISALIGNED_ST when st_misal = '1' else/CAUSE_STORE_FAULT   when st_fault = '1' else CAUSE_MISALIGNED_ST when st_misal = '1' else/" "$trap_af_gens"
mutant "$trap" "$trap_af_props" trap_unit  ''              af_fetch_tval_ea "s/i_pc        when fetch_fault = '1' else/i_ea        when fetch_fault = '1' else/" "$trap_af_gens"
mutant "$trap" "$trap_af_props" trap_unit  ''              af_store_fault_cause_load "s/CAUSE_STORE_FAULT   when st_fault = '1' else/CAUSE_LOAD_FAULT    when st_fault = '1' else/" "$trap_af_gens"

# Mutants of the interrupt entry in the trap unit and in the CSR bank, one defect each.
mutant "$trap" "$trap_props" trap_unit  '-DIRQ'         irq_keeps_mret   "s/ and (not irq_go);/;/"
mutant "$trap" "$trap_props" trap_unit  '-DIRQ'         irq_aborts_fencei "s/ and (not is_fencei);/;/"
mutant "$trap" "$trap_props" trap_unit  '-DIRQ'         irq_dirty_tval   "s/o_tval  <= (others => '0') when irq_go = '1' else/o_tval  <= i_ea when irq_go = '1' else/"
mutant "$trap" "$trap_props" trap_unit  '-DIRQ'         irq_loses_to_exception "s/o_cause <= i_irq_cause when irq_go = '1' else/o_cause <= i_irq_cause when (irq_go = '1' and has_exc = '0') else/"
mutant "$trap" "$trap_props" trap_unit  '-DIRQ'         irq_ignores_run  "s/i_irq_take and i_ex_valid and i_run and/i_irq_take and i_ex_valid and/"
mutant "$trap" "$trap_props" trap_unit  '-DIRQ'         irq_ignores_valid "s/i_irq_take and i_ex_valid and i_run and/i_irq_take and i_run and/"
mutant "$trap" "$trap_props" trap_unit  '-DIRQ'         irq_flag_always  "s/o_irq       <= irq_go;/o_irq       <= i_irq_take;/"
PROBES="$irq_probes"
mutant "$csr" "$csr_irq_props" csr_file '' irq_take_ignores_mie "s/o_irq_take    <= mstatus_mie when/o_irq_take    <= '1' when/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_cause_software_first "s/CAUSE_IRQ_EXTERNAL when irq_pend_vec(IRQ_IDX_EXTERNAL) = '1' else/CAUSE_IRQ_SOFTWARE when irq_pend_vec(IRQ_IDX_SOFTWARE) = '1' else CAUSE_IRQ_EXTERNAL when irq_pend_vec(IRQ_IDX_EXTERNAL) = '1' else/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_cause_timer_first "s/CAUSE_IRQ_EXTERNAL when irq_pend_vec(IRQ_IDX_EXTERNAL) = '1' else/CAUSE_IRQ_TIMER when irq_pend_vec(IRQ_IDX_TIMER) = '1' else CAUSE_IRQ_EXTERNAL when irq_pend_vec(IRQ_IDX_EXTERNAL) = '1' else/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_mtvec_mode_lost "s/mtvec_mode_nxt <= new_value(0) when HAS_INTERRUPTS else '0';/mtvec_mode_nxt <= '0';/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_mtvec_unaligned_vector "s/(others => '0') when mtvec_mode_nxt = '1' else new_value(5 downto 2)/new_value(5 downto 2)/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '-DOFF' irq_mtvec_mode_without_interrupts "s/mtvec_mode <= '0';/mtvec_mode <= i_wdata(0);/" "-ghas_interrupts=false" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_mtvec_bit1_reads_mode "s/mtvec_reg(31 downto 2) \& '0' \& mtvec_mode;/mtvec_reg(31 downto 2) \& mtvec_mode \& mtvec_mode;/" "-ghas_interrupts=true" 6
PROBES=""

# Mutants of the interrupt entry in stage_ex, one defect each (the whole tree is analyzed again for each).
ex_file="$root/src/core/stage_ex.vhd"
mutant_tree() {  # <name> <sed expression>
  local copy="$out/mut_$1.vhd"
  sed "$2" "$ex_file" > "$copy"
  cmp -s "$ex_file" "$copy" && { echo "mutant $1: the edit did not change the file"; exit 1; }
  TREE_REPLACES="src/core/stage_ex.vhd" TREE_COPY="$copy" netlist_tree stage_ex "mut_$1" $ex_gens
  expect "mutant $1 is caught" FAIL "$(prove "mut_$1.v" "$stage_props" bmc 14 '' "mut_$1")"
}
mutant_tree stage_irq_mepc_next "s/i_mem_trap_pc    when i_mem_trap_take = '1' else i_pc;/i_mem_trap_pc    when i_mem_trap_take = '1' else i_pc4;/"
mutant_tree stage_irq_vector_ignored "s/irq_vector_pc  when (trap_is_irq = '1' and csr_mtvec_vec = '1') else/csr_mtvec when (trap_is_irq = '1' and csr_mtvec_vec = '1') else/"
mutant_tree stage_irq_vector_wrong_bits "s/csr_mtvec(31 downto 6) \& trap_cause(3 downto 0) \& BYTE_OFFSET_0;/csr_mtvec(31 downto 6) \& trap_cause(4 downto 1) \& BYTE_OFFSET_0;/"
mutant_tree stage_irq_vector_for_exceptions "s/(trap_is_irq = '1' and csr_mtvec_vec = '1')/(trap_take_int = '1' and csr_mtvec_vec = '1')/"
mutant_tree stage_irq_cause_lost "s/i_irq_cause   => irq_cause,/i_irq_cause   => (others => '0'),/"

mutant "$zim" "$zim_props" zimop_decode '' zimop_funct3_ignored "s/funct3 = FUNCT3_SYSTEM_RESERVED and/true and/" "" 2
mutant "$zim" "$zim_props" zimop_decode '' zimop_bit31_ignored "s/i_instr(31) = ZIMOP_BIT31 and//" "" 2
mutant "$zim" "$zim_props" zimop_decode '' zimop_mop_r_fields_ignored "s/i_instr(24 downto 22) = ZIMOP_BITS_24_22/i_instr(24 downto 23) = ZIMOP_BITS_24_22(2 downto 1)/" "" 2
mutant "$zim" "$zim_props" zimop_decode '' zimop_mop_rr_any_bit25 "s/is_mop_rr <= '1' when (is_common = '1' and i_instr(25) = ZIMOP_BIT25_RR)/is_mop_rr <= '1' when (is_common = '1')/" "" 2
mutant "$zim" "$zim_props" zimop_decode '' zimop_no_write "s/o_we_reg   <= is_mop;/o_we_reg   <= '0';/" "" 2
mutant "$zim" "$zim_props" zimop_decode '' zimop_alu_has_result "s/o_alu_op   <= ALU_BGEU;/o_alu_op   <= ALU_ADD;/" "" 2
mutant "$zim" "$zim_props" zimop_decode '' zimop_keeps_system "s/o_opcode   <= OPCODE_OP_IMM;/o_opcode   <= OPCODE_SYSTEM;/" "" 2

mutant "$ntl" "$ntl_props" zihintntl_decode '' ntl_rd_ignored "s/rd = ZIHINTNTL_REG_ZERO and rs1/rs1/" "" 2
mutant "$ntl" "$ntl_props" zihintntl_decode '' ntl_rs1_ignored "s/ and rs1 = ZIHINTNTL_REG_ZERO and/ and/" "" 2
mutant "$ntl" "$ntl_props" zihintntl_decode '' ntl_funct7_ignored "s/ and funct7 = FUNCT7_DEFAULT//" "" 2
mutant "$ntl" "$ntl_props" zihintntl_decode '' ntl_rs2_too_wide "s/<= unsigned(ZIHINTNTL_RS2_LAST)/<= unsigned(ZIHINTNTL_RS2_LAST) + 1/" "" 2
mutant "$ntl" "$ntl_props" zihintntl_decode '' ntl_rs2_too_low "s/>= unsigned(ZIHINTNTL_RS2_FIRST)/>= unsigned(ZIHINTNTL_RS2_FIRST) - 1/" "" 2

mutant "$pau" "$pau_props" zihintpause_decode '' pause_pred_ignored "s/i_instr(31 downto 20) = ZIHINTPAUSE_FM_PRED_SUCC/i_instr(31 downto 24) = ZIHINTPAUSE_FM_PRED_SUCC(11 downto 4)/" "" 2
mutant "$pau" "$pau_props" zihintpause_decode '' pause_rd_ignored "s/rd = ZIHINTPAUSE_REG_ZERO and rs1/rs1/" "" 2
mutant "$pau" "$pau_props" zihintpause_decode '' pause_funct3_ignored "s/ and funct3 = FUNCT3_FENCE and/ and/" "" 2

mutant "$csr" "$csr_cntr_props" csr_file '' cntr_mirror_writable "s/is_read_only     <= '1' when i_addr(11 downto 10) = CSR_ADDR_READ_ONLY else '0';/is_read_only     <= '0';/" "-ghas_zicntr=true -gtick_cycles=3" 6
mutant "$csr" "$csr_cntr_props" csr_file '' cntr_hi_is_lo "s/minstret_rd_hi when (i_addr = ADDR_MINSTRETH or i_addr = ADDR_INSTRETH)/minstret_rd_lo when (i_addr = ADDR_MINSTRETH or i_addr = ADDR_INSTRETH)/" "-ghas_zicntr=true -gtick_cycles=3" 6

mutant "$csr" "$csr_cntr_props" csr_file '' cntr_inhibit_ignored "s/mcycle_inc     <= not inhibit_reg(0);/mcycle_inc     <= '1';/" "-ghas_zicntr=true -gtick_cycles=3" 6
mutant "$csr" "$csr_cntr_props" csr_file '' cntr_inhibit_instret_ignored "s/ and (not inhibit_reg(2));/;/" "-ghas_zicntr=true -gtick_cycles=3" 6
mutant "$csr" "$csr_cntr_props" csr_file '' cntr_cancel_ignored "s/retire_pending and (not i_retire_cancel) and (not inhibit_reg(2));/retire_pending and (not inhibit_reg(2));/" "-ghas_zicntr=true -gtick_cycles=3" 6
mutant "$csr" "$csr_cntr_props" csr_file '' cntr_pending_unseen "s/unsigned'(0 => retire_pending and (not inhibit_reg(2))));/unsigned'(0 => '0'));/" "-ghas_zicntr=true -gtick_cycles=3" 6

# Mutants of the bank of event counters and of the decoding in csr_file (the proofs above, one defect each).
bank="$root/src/Zihpm/hpm_counter_bank.vhd"
mutant_bank() {  # <file> <props> <defines> <name> <sed expression> <ghdl generics> <bmc depth>
  local copy="$out/mut_$4.vhd"
  sed "$5" "$1" > "$copy"
  cmp -s "$1" "$copy" && { echo "mutant $4: the edit did not change the file"; exit 1; }
  if [ "$1" = "$bank" ]; then
    BANK_FILE="$copy" netlist "$csr" csr_file "mut_$4" "$6"
  else
    netlist "$copy" csr_file "mut_$4" "$6"
  fi
  expect "mutant $4 is caught" FAIL "$(prove "mut_$4.v" "$2" bmc "$7" "$3" "mut_$4")"
}
hpm4="-ghas_zihpm=true -ghpm_counters=4 -ghpm_width=64"
hpm2="-ghas_zihpm=true -ghpm_counters=2 -ghpm_width=40"
mutant_bank "$bank" "$csr_hpm_props" '-DNHPM=4' hpm_inhibit_ignored "s/(not inhibit_q(n - HPM_FIRST_INDEX))/'1'/" "$hpm4" 6
mutant_bank "$bank" "$csr_hpm_props" '-DNHPM=4' hpm_event_table_ignored "s/events_valid <= i_events and EVENT_TABLE_MASK;/events_valid <= i_events;/" "$hpm4" 6
mutant_bank "$bank" "$csr_hpm_props" '-DNHPM=4' hpm_absent_not_zero "s/lo_rows(n)    <= (others => '0');/lo_rows(n)    <= (others => '1');/" "$hpm4" 6
mutant_bank "$bank" "$csr_hpm_props" '-DNHPM=2 -DWIDTH=40' hpm_width_ignored "s/width => hpm_width/width => 64/" "$hpm2" 6
mutant_bank "$bank" "$csr_hpm_props" '-DNHPM=4' hpm_inhibit_reserved_bits "s/inhibit_q(HPM_MAX_COUNTERS - 1 downto REAL_COUNTERS) <= (others => '0');/inhibit_q(HPM_MAX_COUNTERS - 1 downto REAL_COUNTERS) <= (others => '1');/" "$hpm4" 6
mutant_bank "$bank" "$csr_hpm_props" '-DNHPM=4' hpm_write_lost "s/i_we_lo => lo_we,/i_we_lo => '0',/" "$hpm4" 6
mutant_bank "$bank" "$csr_hpm_props" '-DNHPM=4' hpm_event_write_lost "s/i_enable => event_we,/i_enable => '0',/" "$hpm4" 6
mutant_bank "$csr" "$csr_hpm_props" '-DNHPM=4' hpm_mirror_writable "s/is_read_only     <= '1' when i_addr(11 downto 10) = CSR_ADDR_READ_ONLY else '0';/is_read_only     <= '0';/" "$hpm4" 6
mutant_bank "$csr" "$csr_hpm_props" '-DNHPM=4' hpm_undefined_index_legal "s/(idx_is_hpm and (in_event_range or in_lo_range or in_hi_range or (to_sl(HAS_SSCOF) and in_eventh_range)))/(in_event_range or in_lo_range or in_hi_range)/" "$hpm4" 6
mutant_bank "$csr" "$csr_hpm_props" '-DNHPM=4' hpm_range_overlap "s/in_event_range   <= '1' when addr_range = RANGE_MHPMEVENT else '0';/in_event_range   <= '1' when addr_range(6 downto 2) = RANGE_MHPMEVENT(6 downto 2) else '0';/" "$hpm4" 6
# Mutants of the Sscofpmf extension.
ofp="-DNHPM=2 -DWIDTH=3"
mutant_bank "$csr" "$csr_time_props" '' time_halves_swapped "s/time_lo   <= i_mtime(31 downto 0);/time_lo   <= i_mtime(63 downto 32);/" "$time_gens" 4
mutant_bank "$csr" "$csr_time_props" '' time_hi_zero "s/time_hi   <= i_mtime(63 downto 32);/time_hi   <= (others => '0');/" "$time_gens" 4
mutant_bank "$bank" "$csr_ofp_props" "$ofp" ofp_request_ignores_of "s/ovf_req(n)     <= wrap and (not of_q);/ovf_req(n)     <= wrap;/" "$ofp_gens" 10
mutant_bank "$bank" "$csr_ofp_props" "$ofp" ofp_overflow_loses_to_write "s/of_d      <= wrap or i_wdata(31);/of_d      <= i_wdata(31);/" "$ofp_gens" 10
mutant_bank "$bank" "$csr_ofp_props" "$ofp" ofp_minh_ignored "s/ and (not minh_q);/;/" "$ofp_gens" 10
mutant_bank "$bank" "$csr_ofp_props" "$ofp" ofp_of_not_sticky "s/of_en     <= wrap or eventh_we;/of_en     <= eventh_we;/" "$ofp_gens" 10
mutant_bank "$csr" "$csr_ofp_props" "$ofp" ofp_lcofi_before_timer "s/CAUSE_IRQ_LCOFI    when (lcofi_pend = '1' and irq_pend_vec(IRQ_IDX_TIMER) = '0') else/CAUSE_IRQ_LCOFI    when lcofi_pend = '1' else/" "$ofp_gens" 10
mutant_bank "$csr" "$csr_ofp_props" "$ofp" ofp_lcofip_write_lost "s/lcofip_we  <= ovf_irq or (csr_write_valid and to_sl(i_addr = ADDR_MIP) and (not i_trap_take) and (not i_mret_take));/lcofip_we  <= ovf_irq;/" "$ofp_gens" 10
mutant_bank "$csr" "$csr_ofp_props" "$ofp" ofp_lcofie_ignored "s/lcofi_pend <= lcofip and lcofie;/lcofi_pend <= lcofip;/" "$ofp_gens" 10
mutant_bank "$csr" "$csr_ofp_props" "$ofp" ofp_eventh_range_alias "s/in_eventh_range  <= '1' when addr_range = RANGE_MHPMEVENTH else '0';/in_eventh_range  <= '1' when addr_range(5 downto 0) = RANGE_MHPMEVENTH(5 downto 0) else '0';/" "$ofp_gens" 10

# Mutants of the interrupts in csr_file, one defect each.
PROBES="$irq_probes"
mutant "$csr" "$csr_irq_props" csr_file '' irq_lines_swapped "s/(i_irq_external \& i_irq_timer \& i_irq_software)/(i_irq_external \& i_irq_software \& i_irq_timer)/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_pending_unmasked "s/irq_pend_vec  <= irq_in and irq_en_reg;/irq_pend_vec  <= irq_in;/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_mie_write_lost "s/i_enable => irq_en_we,/i_enable => '0',/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_mie_bit_moved "s/irq_en_nxt(IRQ_IDX_TIMER)    <= new_value(IRQ_BIT_TIMER);/irq_en_nxt(IRQ_IDX_TIMER)    <= new_value(IRQ_BIT_EXTERNAL);/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '' irq_mie_read_wrong_bit "s/IRQ_BIT_TIMER    => irq_en_reg(IRQ_IDX_TIMER),/IRQ_BIT_TIMER    => irq_en_reg(IRQ_IDX_SOFTWARE),/" "-ghas_interrupts=true" 6
mutant "$csr" "$csr_irq_props" csr_file '-DOFF' irq_ports_not_gated "s/when HAS_INTERRUPTS else (others => '0');/when true else (others => '0');/" "-ghas_interrupts=false" 6
PROBES=""

mutant "$fus" "$fus_props" muldiv_fusion '' fusion_ignores_b      "s/(i_a = rec_a and i_b = rec_b)/(i_a = rec_a)/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_family_confused "s/i_funct3(2) = rec_funct3(2) and//" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_sign_ignored   "s/(i_funct3(2) = '0' or i_funct3(0) = rec_funct3(0))/true/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_same_op        "s/i_funct3 \/= rec_funct3 and//" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_no_check_cycle "s/hit   <= check_q and rec_valid/hit   <= rec_valid/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_record_on_start "0,/i_enable => i_done/s//i_enable => i_start/" "" 10


mutant "$zc" "$zc_props" zicond_unit '' zc_eqz_inverted   "s/(is_eqz and rs2_zero)/(is_eqz and not rs2_zero)/" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_nez_inverted   "s/(is_nez and not rs2_zero)/(is_nez and rs2_zero)/" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_eqz_never_zero "s/(is_eqz and rs2_zero) or //" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_eqz_always_zero "s/(is_eqz and rs2_zero)/is_eqz/" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_nez_never_zero "s/ or (is_nez and not rs2_zero)//" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_nez_always_zero "s/(is_nez and not rs2_zero)/is_nez/" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_result_is_rs2 "s/else i_rs1;/else i_rs2;/" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_rs2_msb_ignored "s/'1' when i_rs2 = (i_rs2'range => '0')/'1' when i_rs2(30 downto 0) = (30 downto 0 => '0')/" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_only_eqz_active "s/o_active <= is_eqz or is_nez;/o_active <= is_eqz;/" "" 2
mutant "$zc" "$zc_props" zicond_unit '' zc_nez_code_taken_by_eqz "s/'1' when i_op = ALU_CZERO_EQZ else/'1' when i_op(3 downto 0) = ALU_CZERO_EQZ(3 downto 0) else/" "" 2

mutant "$zd" "$zd_props" zicond_decode '' zd_funct7_lsb_ignored "0,/funct7 = FUNCT7_ZICOND and funct3 = FUNCT3_CZERO_EQZ/s//funct7(6 downto 1) = FUNCT7_ZICOND(6 downto 1) and funct3 = FUNCT3_CZERO_EQZ/" "" 2
mutant "$zd" "$zd_props" zicond_decode '' zd_opcode_ignored "s/'1' when (opcode = OPCODE_OP and funct7 = FUNCT7_ZICOND and funct3 = FUNCT3_CZERO_NEZ)/'1' when (funct7 = FUNCT7_ZICOND and funct3 = FUNCT3_CZERO_NEZ)/" "" 2
mutant "$zd" "$zd_props" zicond_decode '' zd_codes_swapped "s/ALU_CZERO_EQZ when is_eqz = '1' else/ALU_CZERO_NEZ when is_eqz = '1' else/" "" 2
mutant "$zd" "$zd_props" zicond_decode '' zd_no_write "s/o_we_reg     <= is_eqz or is_nez;/o_we_reg     <= '0';/" "" 2
mutant "$zd" "$zd_props" zicond_decode '' zd_no_rs1 "s/o_sel_pc_rs1 <= is_eqz or is_nez;/o_sel_pc_rs1 <= is_eqz;/" "" 2
mutant "$zd" "$zd_props" zicond_decode '' zd_funct3_one_bit "s/funct3 = FUNCT3_CZERO_NEZ) else/funct3(1 downto 0) = FUNCT3_CZERO_NEZ(1 downto 0)) else/" "" 2

# Mutants of o_trap_take in core.vhd, one defect each.
core_mutant() {  # <name> <sed expression> <mode: bmc|cover> <defines>
  local copy="$out/mut_$1.vhd"
  sed "$2" "$core_file" > "$copy"
  cmp -s "$core_file" "$copy" && { echo "mutant $1: the edit did not change the file"; exit 1; }
  CORE_FILE="$copy" core_netlist "mut_$1" -ghas_zicsr=true
  expect "mutant $1 is caught" FAIL "$(prove "mut_$1.v" "$core_props" "$3" 10 "$4" "mut_$1")"
}
core_mutant take_always "s/o_trap_take   <= any_trap_take or trap_sig;/o_trap_take   <= '1';/" bmc ''
core_mutant take_never  "s/o_trap_take   <= any_trap_take or trap_sig;/o_trap_take   <= '0';/" cover '-DCOVER'
core_mutant take_with_retire "s/o_trap_take   <= any_trap_take or trap_sig;/o_trap_take   <= any_trap_take or trap_sig or retire_pulse;/" bmc ''
CONFIG_FILE="$(config_variant faults_map)" mutant "$exmem" "$exmem_props" reg_ex_mem '' exmem_slots_ignored "s/periph_slots or (7 downto 0 => to_sl(not STRICT_PERIPH))/(others => '1')/" "$exmem_gens" 6
CONFIG_FILE="$(config_variant faults_map)" mutant "$exmem" "$exmem_props" reg_ex_mem '' exmem_strict_inverted "s/to_sl(not STRICT_PERIPH)/to_sl(STRICT_PERIPH)/" "$exmem_gens" 6
mutant "$alu" "$alu_props" alu '' alu_sra_fill_ignored   "s/shift_fill   <= op_inv and i_a(data_width-1);/shift_fill   <= '0';/" "" 2
mutant "$alu" "$alu_props" alu '' alu_slt_wrong_bit      "s/else sum_ext(data_width-1);/else sum_ext(data_width);/" "" 2
mutant "$alu" "$alu_props" alu '' alu_jalr_keeps_bit0    "s/(sum_ext(0) and not is_jalr)/sum_ext(0)/" "" 2
mutant "$alu" "$alu_props" alu '' alu_srl_digit_two      "s/shift_right_fill(shr_stage(p), 2 \* 4 \*\* p, shift_fill) when SHIFT_DIGIT_2/shift_right_fill(shr_stage(p), 3 * 4 ** p, shift_fill) when SHIFT_DIGIT_2/" "" 2
mutant "$alu" "$alu_props" alu '' alu_sll_digit_one      "s/shift_left_zero(shl_stage(p), 1 \* 4 \*\* p)     when SHIFT_DIGIT_1/shift_left_zero(shl_stage(p), 2 * 4 ** p)     when SHIFT_DIGIT_1/" "" 2
mutant "$alu" "$alu_props" alu '' alu_bgeu_inverted      "s/is_branch and not lt_unsigned  *when FUNCT3_BGEU/is_branch and lt_unsigned when FUNCT3_BGEU/" "" 2
mutant "$alu" "$alu_props" alu '' alu_equal_low_bit      "s/'1' when i_a = i_b else '0'/'1' when i_a(data_width-1 downto 1) = i_b(data_width-1 downto 1) else '0'/" "" 2
mutant "$alu" "$alu_props" alu '' alu_lui_adds_a         "s/(others => '0') when is_lui = '1' else i_a/i_a/" "" 2
mutant "$alu" "$alu_props" alu '' alu_sub_no_carry       "s/carry_in  <= (0 => op_inv);/carry_in  <= (0 => '0');/" "" 2
mutant "$alu" "$alu_props" alu '' alu_xor_selects_or     "s/and (i_a xor i_b)/and (i_a or i_b)/" "" 2

[ -s "$warnings" ] && { echo "formal: $(wc -l < "$warnings") warning(s) found; a warning is an error (see above)"; fail=1; }
[ "$fail" -eq 0 ] && echo "formal: all expectations met" || { echo "formal: FAILED (logs in build/formal)"; exit 1; }
