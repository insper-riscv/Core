#!/usr/bin/env bash
# Formal verification of the CSR bank and the trap unit with SymbiYosys. Needs ghdl, yosys, sby and
# the z3 solver (all in the dev_tools image). Run from the root of the repository:  bash formal/run.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/formal"
rm -rf "$out"; mkdir -p "$out"; cd "$out"

fail=0
# expect <label> <wanted: PASS|FAIL> <result: PASS|FAIL>
expect() {
  if [ "$2" = "$3" ]; then printf '  ok    %-62s %s\n' "$1" "$3"
  else printf '  WRONG %-62s wanted %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}

# netlist <vhdl> <entity> <name> [ghdl generics]: the Verilog netlist GHDL synthesizes for the entity.
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
    "$root/src/Zicntr/counter64.vhd" \
    "$root/src/Zicntr/tick_divider.vhd" \
    "$1"
  ghdl --synth --std=08 --workdir="$work" --out=verilog ${4:-} "$2" > "$3.v"
}

# prove <netlist> <props> <mode: prove|bmc|cover> <depth> <defines> <tag>  ->  PASS or FAIL
prove() {
  cat > "$6.sby" <<EOS
[options]
mode $3
depth $4
[engines]
smtbmc z3
[script]
read_verilog -formal -sv $5 $1 $2
prep -top props
[files]
$1
$2
EOS
  if sby -f "$6.sby" > "$6.log" 2>&1; then echo PASS; else echo FAIL; fi
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
netlist "$trap" trap_unit trap_ext -gext_flash=true
expect "sdram map: misaligned in the flash and the SDRAM runs, elsewhere traps (induction)" PASS "$(prove trap_ext.v "$trap_props" prove 2 '-DZICCLSM_ON -DEXT_FLASH' trap_zicclsm_ext)"

echo "counter64"
cnt="$root/src/Zicntr/counter64.vhd"; cnt_props="$root/formal/counter64_props.sv"
netlist "$cnt" counter64 cnt
expect "the value shown is the ideal 64-bit counter, carry and writes (induction)" PASS "$(prove cnt.v "$cnt_props" prove 4 ''           cnt_safety)"
expect "monotonic without a write (induction)"                                   PASS "$(prove cnt.v "$cnt_props" prove 4 '-DMONOTONIC' cnt_monotonic)"
expect "cover: the carry between the halves is reachable"                        PASS "$(prove cnt.v "$cnt_props" cover 12 '-DCOVER'    cnt_cover)"

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
netlist "$csr" csr_file csrh "-ghpm_counters=4"
# The event counters share the counter64 already proven, so this proof is bounded from reset: it checks the wiring (addresses, halves, event selection, inhibit bits, write path, legality).
expect "events, inhibit, selectors and counters follow the models, mirrors read-only (bounded, 6 cycles)" PASS "$(prove csrh.v "$csr_hpm_props" bmc 6 '-DNHPM=4' csrh_safety)"
expect "cover: a count at the carry point, an inhibited event and a write with a count are reachable"  PASS "$(prove csrh.v "$csr_hpm_props" cover 12 '-DNHPM=4 -DCOVER' csrh_cover)"
netlist "$csr" csr_file csrh2 "-ghpm_counters=2 -ghas_zicntr=true -gtick_cycles=3"
expect "two event counters with Zicntr: the other two are illegal, mcycle/minstret own bits 0 and 2 (bounded, 6 cycles)" PASS "$(prove csrh2.v "$csr_hpm_props" bmc 6 '-DNHPM=2 -DHAS_CNTR' csrh2_safety)"

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

mutant "$csr" "$csr_hpm_props" csr_file '-DNHPM=4' hpm_inhibit_ignored "s/(not inhibit_reg(3 + k));/'1';/" "-ghpm_counters=4" 6
mutant "$csr" "$csr_hpm_props" csr_file '-DNHPM=4' hpm_code_zero_counts "s/bool_to_sl(event_code(k) \/= std_logic_vector(to_unsigned(EVENT_NONE, EVENT_CODE_WIDTH))) and/'1' and/" "-ghpm_counters=4" 6
mutant "$csr" "$csr_hpm_props" csr_file '-DNHPM=2' hpm_mask_wide "s/mask(3 + k) := '1';/mask(3 + k) := '1'; mask(6) := '1';/" "-ghpm_counters=2" 6

mutant "$fus" "$fus_props" muldiv_fusion '' fusion_ignores_b      "s/(i_a = rec_a and i_b = rec_b)/(i_a = rec_a)/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_family_confused "s/i_funct3(2) = rec_funct3(2) and//" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_sign_ignored   "s/(i_funct3(2) = '0' or i_funct3(0) = rec_funct3(0))/true/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_same_op        "s/i_funct3 \/= rec_funct3 and//" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_no_check_cycle "s/hit   <= check_q and rec_valid/hit   <= rec_valid/" "" 10
mutant "$fus" "$fus_props" muldiv_fusion '' fusion_record_on_start "0,/i_enable => i_done/s//i_enable => i_start/" "" 10

mutant "$cnt" "$cnt_props" counter64 '' carry_lost        "s/lo = WORD_ALL_ONES/lo = WORD_INT_MIN/"
mutant "$cnt" "$cnt_props" counter64 '' write_adds_one    "s/lo_nxt <= i_wdata when/lo_nxt <= std_logic_vector(unsigned(i_wdata) + 1) when/"
mutant "$cnt" "$cnt_props" counter64 '' no_increment_idle "s/lo_en  <= i_we_lo or i_inc;/lo_en  <= i_we_lo;/"

[ "$fail" -eq 0 ] && echo "formal: all expectations met" || { echo "formal: FAILED (logs in build/formal)"; exit 1; }
