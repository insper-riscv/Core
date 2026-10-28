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
    "$root/common/pipeline_types.vhd" \
    "$root/common/byte_mask_consts.vhd" \
    "$root/common/opcode_consts.vhd" \
    "$root/common/funct3_consts.vhd" \
    "$root/Common-Components/src/flip_flop.vhd" \
    "$root/Common-Components/src/generic_register.vhd" \
    "$root/common/mem_map_consts.vhd" \
    "$root/Zicsr/csr_addr_consts.vhd" \
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

csr="$root/Zicsr/csr_file.vhd"; csr_props="$root/formal/csr_file_props.sv"
trap="$root/Zicsr/trap_unit.vhd"; trap_props="$root/formal/trap_unit_props.sv"

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
netlist "$trap" trap_unit trap_off -gHAS_ZICCLSM=false
expect "no Zicclsm: every misaligned access traps (induction)"                PASS "$(prove trap_off.v "$trap_props" prove 2 '-DZICCLSM_OFF' trap_zicclsm_off)"

# Mutants of the VHDL: each defect must make a proof fail.
mutant() {  # <file> <props> <entity> <defines> <name> <sed expression>
  local copy="$out/mut_$5.vhd"
  sed "$6" "$1" > "$copy"
  cmp -s "$1" "$copy" && { echo "mutant $5: the edit did not change the file"; exit 1; }
  netlist "$copy" "$3" "mut_$5"
  expect "mutant $5 is caught" FAIL "$(prove "mut_$5.v" "$2" bmc 8 "$4" "mut_$5")"
}
mutant "$csr"  "$csr_props"  csr_file  '-DMSTATUS_MODE' trap_keeps_mie  "s/mie_nxt <= '0'          when i_trap_take = '1'/mie_nxt <= mstatus_mie  when i_trap_take = '1'/"
mutant "$csr"  "$csr_props"  csr_file  '-DMSTATUS_MODE' mret_no_mpie    "s/'1'         when i_mret_take = '1'/'0'         when i_mret_take = '1'/"
mutant "$csr"  "$csr_props"  csr_file  ''               mepc_odd         "s/new_value(31 downto 2) \& \"00\";/new_value;/"
mutant "$csr"  "$csr_props"  csr_file  ''               trap_no_mcause   "s/mcause_nxt  <= i_trap_cause when i_trap_take = '1' else new_value;/mcause_nxt  <= mcause_reg   when i_trap_take = '1' else new_value;/"
mutant "$trap" "$trap_props" trap_unit  ''              load_halfword    "s/((i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU) and i_ea(0) = '1')/((i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU) and i_ea(1) = '1')/"
mutant "$trap" "$trap_props" trap_unit  ''              mret_any_imm     "s/is_mret   <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_MRET)/is_mret   <= '1' when (is_system = '1' and no_regs = '1')/"
mutant "$trap" "$trap_props" trap_unit  '-DZICCLSM_ON' crossing_any_region "s/ and same_region = '1'//"
mutant "$trap" "$trap_props" trap_unit  '-DZICCLSM_ON' in_word_any_region  "s/in_main_mem = '1' and i_ea(1 downto 0) = BYTE_OFFSET_1/i_ea(1 downto 0) = BYTE_OFFSET_1/"
mutant "$trap" "$trap_props" trap_unit  ''              illegal_ignored  "s/has_exc <= cf_misal or i_illegal or/has_exc <= cf_misal or/"

[ "$fail" -eq 0 ] && echo "formal: all expectations met" || { echo "formal: FAILED (logs in build/formal)"; exit 1; }
