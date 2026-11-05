#!/usr/bin/env bash
# Formal verification of the CSR bank, the trap unit, the counters and the fusion record with SymbiYosys. Needs
# ghdl, yosys, sby and the engine chosen by FORMAL_ENGINE (all in the ci-vhdl image). Run from the root of the
# repository:  FORMAL_ENGINE=bitwuzla bash formal/run.sh
#
# FORMAL_ENGINE is one of yices, bitwuzla (the default), boolector and abc-bmc3. The first three are SMT solvers
# of the smtbmc engine; abc-bmc3 is the bounded model checker of ABC, which has no induction and no cover, so it
# skips those proofs. FORMAL_TIMEOUT (seconds, 900 by default) bounds each proof.
#
# Besides the report, the run writes build/formal/result-<engine>.tsv, one line per proof with the columns
# id, wanted (pass or fail), verdict (pass, fail, error or skip), sby exit code, milliseconds and the label, which
# formal/aggregate.sh joins across engines.
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

# netlist <vhdl> <entity> <name> [ghdl generics]: the Verilog netlist GHDL synthesizes for the entity, with the
# bank of event counters of BANK_FILE (the real one by default).
netlist() {
  local work="$out/work_$3"; mkdir -p "$work"
  ghdl -a --std=08 --workdir="$work" \
    "$root/src/shared/pipeline_types.vhd" \
    "$root/src/shared/byte_mask_consts.vhd" \
    "$root/src/shared/opcode_consts.vhd" \
    "$root/src/shared/funct3_consts.vhd" \
    "$root/src/common/src/flip_flop.vhd" \
    "$root/src/common/src/generic_register.vhd" \
    "$root/src/shared/mem_map_consts.vhd" \
    "$root/src/shared/word_consts.vhd" \
    "$root/src/Zicsr/trap_consts.vhd" \
    "$root/src/Zicsr/csr_addr_consts.vhd" \
    "$root/src/Zicsr/csr_event_consts.vhd" \
    "$root/src/Zicsr/csr_value_consts.vhd" \
    "$root/src/common/src/utils_pkg.vhd" \
    "$root/src/common/src/mux_tree.vhd" \
    "$root/src/Zicntr/counter64.vhd" \
    "$root/src/Zicntr/tick_divider.vhd" \
    "${BANK_FILE:-$root/src/Zihpm/hpm_counter_bank.vhd}" \
    "$1"
  ghdl --synth --std=08 --workdir="$work" --out=verilog ${@:4} "$2" > "$3.v"
}

# prove <netlist> <props> <mode: prove|bmc|cover> <depth> <defines> <tag>  ->  PASS, FAIL, SKIP or ERROR
# PASS is sby exit code 0, FAIL is 2 (a counterexample or a goal that cannot be covered) and any other code
# (4 unknown, 8 timeout, 16 error, 124 the FORMAL_TIMEOUT) is ERROR: the tool did not reach a verdict. The
# abc-bmc3 engine only checks bounded properties of designs with registers, so it answers SKIP for a proof by
# induction, for a cover and for a combinational design.
# The verdict, the exit code and the milliseconds go to <tag>.res, and the tag to .last, for expect.
prove() {
  echo "$6" > "$out/.last"
  local engine_lines script_lines options_lines="" rc=0 verdict began ended
  case "$engine" in
    abc-bmc3)
      if [ "$3" != bmc ]; then
        printf 'SKIP\t-\t0\n' > "$6.res"; echo "SKIP abc-bmc3 has no $3"; return
      fi
      engine_lines="abc bmc3"
      options_lines="aigsmt none"
      script_lines=$'techmap\nopt -fast\nsetundef -anyseq' ;;
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
  # not do, not a failure of the tool.
  if [ "$engine" = abc-bmc3 ] && [ "$rc" = 16 ] && grep -q 'Does not work for combinational networks' "$6.log"; then
    printf 'skip\t%s\t0\n' "$rc" > "$6.res"; echo "SKIP abc-bmc3 does not work for a combinational design"; return
  fi
  case "$rc" in
    0) verdict=PASS ;;
    2) verdict=FAIL ;;
    *) verdict=ERROR ;;
  esac
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
netlist "$trap" trap_unit trap_ext -grom_external=true -grom_end_kib=0 -gext_base_kib=524288 -gperiph_base_kib=1572864 -gram_base_kib=1048576 -gram_end_kib=1572864
expect "sdram map: misaligned in the flash and the SDRAM runs, elsewhere traps (induction)" PASS "$(prove trap_ext.v "$trap_props" prove 2 '-DZICCLSM_ON -DEXT_FLASH' trap_zicclsm_ext)"

echo "counter64"
cnt="$root/src/Zicntr/counter64.vhd"; cnt_props="$root/formal/counter64_props.sv"
netlist "$cnt" counter64 cnt
expect "the value shown is the ideal 64-bit counter, carry and writes (induction)" PASS "$(prove cnt.v "$cnt_props" prove 4 ''           cnt_safety)"
expect "monotonic without a write (induction)"                                   PASS "$(prove cnt.v "$cnt_props" prove 4 '-DMONOTONIC' cnt_monotonic)"
expect "cover: the carry between the halves is reachable"                        PASS "$(prove cnt.v "$cnt_props" cover 12 '-DCOVER'    cnt_cover)"
for w in 1 20 32 33 63; do
  netlist "$cnt" counter64 "cnt$w" "-gwidth=$w"
  expect "width $w: the value shown is the ideal counter of that width, writes truncated (induction)" PASS "$(prove "cnt$w.v" "$cnt_props" prove 4 "-DWIDTH=$w" "cnt${w}_safety")"
done

echo "muldiv_fusion"
fus="$root/src/M/muldiv_fusion.vhd"; fus_props="$root/formal/muldiv_fusion_props.sv"
netlist "$fus" muldiv_fusion fus
# The record mirrors the units' last full result, so this proof is bounded from reset: the fusion is a hit only on the rule and shows the full result of the earlier execution.
expect "hit only on the same values, family and another operation; the record is the last full result (bounded, 10 cycles)" PASS "$(prove fus.v "$fus_props" bmc 10 '' fus_safety)"
expect "cover: a hit in each family and the near misses are reachable" PASS "$(prove fus.v "$fus_props" cover 10 '-DCOVER' fus_cover)"

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

# Mutants of the VHDL: each defect must make a proof fail.
mutant() {  # <file> <props> <entity> <defines> <name> <sed expression> [ghdl generics] [bmc depth]
  local copy="$out/mut_$5.vhd"
  sed "$6" "$1" > "$copy"
  cmp -s "$1" "$copy" && { echo "mutant $5: the edit did not change the file"; exit 1; }
  netlist "$copy" "$3" "mut_$5" "${7:-}"
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
mutant "$trap" "$trap_props" trap_unit  ''              illegal_ignored  "s/has_exc <= cf_misal or i_illegal or/has_exc <= cf_misal or/"

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
mutant_bank "$csr" "$csr_hpm_props" '-DNHPM=4' hpm_undefined_index_legal "s/(idx_is_hpm and (in_event_range or in_lo_range or in_hi_range))/(in_event_range or in_lo_range or in_hi_range)/" "$hpm4" 6
mutant_bank "$csr" "$csr_hpm_props" '-DNHPM=4' hpm_range_overlap "s/in_event_range   <= '1' when addr_range = RANGE_MHPMEVENT else '0';/in_event_range   <= '1' when addr_range(6 downto 2) = RANGE_MHPMEVENT(6 downto 2) else '0';/" "$hpm4" 6

mutant "$fus" "$fus_props" muldiv_fusion '' fusion_ignores_b      "s/(i_a = rec_a and i_b = rec_b)/(i_a = rec_a)/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_family_confused "s/i_funct3(2) = rec_funct3(2) and//" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_sign_ignored   "s/(i_funct3(2) = '0' or i_funct3(0) = rec_funct3(0))/true/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_same_op        "s/i_funct3 \/= rec_funct3 and//" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_no_check_cycle "s/hit   <= check_q and rec_valid/hit   <= rec_valid/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_record_on_start "0,/i_enable => i_done/s//i_enable => i_start/" "" 10

mutant "$cnt" "$cnt_props" counter64 '' carry_lost        "s/lo = LO_ALL_ONES/lo(lo'high) = '1'/"
mutant "$cnt" "$cnt_props" counter64 '-DWIDTH=33' width_one_bit_wider "s/HI_WIDTH : natural := width - LO_WIDTH;/HI_WIDTH : natural := width - LO_WIDTH + 1;/" "-gwidth=33"
mutant "$cnt" "$cnt_props" counter64 '' write_adds_one    "s/lo_nxt <= i_wdata(LO_WIDTH - 1 downto 0) when/lo_nxt <= std_logic_vector(unsigned(i_wdata(LO_WIDTH - 1 downto 0)) + 1) when/"
mutant "$cnt" "$cnt_props" counter64 '' no_increment_idle "s/lo_en  <= i_we_lo or i_inc;/lo_en  <= i_we_lo;/"

[ "$fail" -eq 0 ] && echo "formal: all expectations met" || { echo "formal: FAILED (logs in build/formal)"; exit 1; }
