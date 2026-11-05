#!/usr/bin/env bash
# Tests of formal/aggregate.sh over made-up results:  bash formal/aggregate_test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

# row <id> <wanted> <verdict>: a line of a result file.
row() { printf '%s\t%s\t%s\t0\t10\tlabel of %s\n' "$1" "$2" "$3" "$1"; }

# check <name> <wanted exit code> <directory>: runs the aggregator and compares its exit code.
check() {
  local code=0
  bash "$here/aggregate.sh" "$3" > "$work/out.txt" 2>&1 || code=$?
  if [ "$code" = "$2" ]; then echo "ok    $1"; else echo "WRONG $1: exit $code, wanted $2"; cat "$work/out.txt"; failures=$((failures + 1)); fi
}

d="$work/agree"; mkdir "$d"
{ row p1 pass pass; row m1 fail fail; } > "$d/result-yices.tsv"
{ row p1 pass pass; row m1 fail fail; } > "$d/result-bitwuzla.tsv"
check "every engine agrees with what is wanted" 0 "$d"

d="$work/one-error"; mkdir "$d"
{ row p1 pass pass; row m1 fail fail; } > "$d/result-bitwuzla.tsv"
{ row p1 pass error; row m1 fail error; } > "$d/result-yices.tsv"
check "an engine with an error does not stop another from deciding" 0 "$d"

d="$work/skip"; mkdir "$d"
{ row p1 pass pass; row c1 pass pass; } > "$d/result-bitwuzla.tsv"
{ row p1 pass pass; row c1 pass skip; } > "$d/result-abc-bmc3.tsv"
check "a skip is not an answer, and the other engine decides" 0 "$d"

d="$work/disagree"; mkdir "$d"
{ row p1 pass pass; } > "$d/result-bitwuzla.tsv"
{ row p1 pass fail; } > "$d/result-yices.tsv"
check "one engine says pass and another says fail" 1 "$d"

d="$work/nobody"; mkdir "$d"
{ row p1 pass error; } > "$d/result-bitwuzla.tsv"
{ row p1 pass skip; } > "$d/result-abc-bmc3.tsv"
check "no engine answered a proof" 1 "$d"

d="$work/only-broken"; mkdir "$d"
{ row p1 pass error; row m1 fail error; } > "$d/result-yices.tsv"
check "the only engine is broken" 1 "$d"

d="$work/wanted-fail-passed"; mkdir "$d"
{ row m1 fail pass; } > "$d/result-bitwuzla.tsv"
{ row m1 fail pass; } > "$d/result-yices.tsv"
check "the engines agree on pass where fail is wanted" 1 "$d"

d="$work/missing-engine"; mkdir "$d"
{ row p1 pass pass; row p2 pass pass; } > "$d/result-bitwuzla.tsv"
{ row p1 pass pass; } > "$d/result-yices.tsv"
check "an engine that lacks a proof leaves it to the others" 0 "$d"

d="$work/empty"; mkdir "$d"
check "no result file at all" 1 "$d"

# The guard against warnings (scan_warnings of formal/warnings.sh). Each case is a log line and whether the guard
# must find a warning in it.
guard_case() {  # <wanted: warn|clean> <log line> <what the line shows> [engine] [log name] [skipped]
  local found log="$work/${5:-guard.log}"
  printf '%s\n' "$2" > "$log"
  : > "$work/warnings.txt"
  found="$(engine="${4:-bitwuzla}" root="$work" warnings="$work/warnings.txt" bash -c 'source "$1"; scan_warnings "$2" "$3" 2>&1' _ "$here/warnings.sh" "$log" "${6:-}")"
  if { [ "$1" = warn ] && [ -n "$found" ] && [ -s "$work/warnings.txt" ]; } || { [ "$1" = clean ] && [ -z "$found" ] && [ ! -s "$work/warnings.txt" ]; }; then
    echo "ok    guard: $3"
  else
    echo "WRONG guard: $3 (wanted $1, found '$found')"; failures=$((failures + 1))
  fi
}
guard_case warn  '/w/src/Zicntr/counter64.vhd:3:8:warning: entity "counter64" was also defined in file [-Wlibrary]' "a warning of GHDL" bitwuzla guard.ghdl.log
guard_case warn  'src/common/src/mux_tree.vhd:9:9:warning: no assignment for offsets 0:0 of signal "mux_levels"' "an injected warning of GHDL"
guard_case warn  'SBY 12:00:01 [mut_x] base: Warning: Wire props.\x is used but has no driver.' "a warning of Yosys in the log of SymbiYosys"
guard_case warn  'WARNING: something' "the word in capitals"
guard_case warn  'Warnings: 2 unique messages, 2 total' "a summary of Yosys with a count above zero"
guard_case clean 'Warnings: 0 unique messages, 0 total' "a summary of Yosys with a count of zero"
guard_case clean 'reading formal/no_warnings.sv' "a file name that contains the word"
guard_case clean 'assert property warning_count passed' "a name that contains the word"
guard_case clean 'SBY 12:00:03 [safety] aig: Warning: Treating undriven bit props.\clk like $anyseq.' "an ABC message, in the abc-bmc3 engine" abc-bmc3
guard_case clean 'SBY 12:00:03 [safety] aig: Warning: Treating a total of 7 undriven bits in props like $anyseq.' "an ABC message with a count, in the abc-bmc3 engine" abc-bmc3
guard_case clean 'SBY 12:00:03 [safety] engine_0: Warning: The last 2 outputs are interpreted as constraints.' "an ABC message about constraints, in the abc-bmc3 engine" abc-bmc3
for e in yices bitwuzla boolector; do
  guard_case warn  'SBY 12:00:03 [safety] aig: Warning: Treating undriven bit props.\clk like $anyseq.' "the same ABC message in $e" "$e"
done
guard_case warn  'SBY 12:00:03 [safety] base: Warning: Wire props.\x is used but has no driver.' "any other warning, in the abc-bmc3 engine" abc-bmc3
guard_case warn  'aig: Warning: Treating undriven bit props.\clk like $anyseq.' "an ABC message in a GHDL log of the abc-bmc3 engine" abc-bmc3 guard.ghdl.log
guard_case warn  'SBY 12:00:03 [safety] engine_0: Warning: The network is combinational.' "the combinational message of ABC, outside a skipped proof" abc-bmc3
guard_case clean 'SBY 12:00:03 [safety] engine_0: Warning: The network is combinational.' "the combinational message of ABC, in a skipped proof" abc-bmc3 guard.log skipped
guard_case clean 'SBY 12:00:02 [safety] summary: engine_0 (smtbmc bitwuzla) returned pass' "an ordinary line"

[ "$failures" -eq 0 ] && echo "aggregate: all tests passed" || { echo "aggregate: $failures test(s) failed"; exit 1; }
