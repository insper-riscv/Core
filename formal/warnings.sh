#!/usr/bin/env bash
# The guard of formal/run.sh against warnings: a warning of GHDL, Yosys or SymbiYosys is an error. This file only
# defines abc_notes and scan_warnings, and is sourced by formal/run.sh and by formal/aggregate_test.sh, which
# test it. The script that sources it sets root, engine and warnings (the file where the findings are recorded).

# abc_notes: one exception, exact and only for the abc-bmc3 engine. ABC itself prints "Warning:" about the AIGER
# file that SymbiYosys hands it (the clock input is consumed by the clk2ff step, and ABC announces how many outputs
# it reads as constraints, or that there is none). They describe the tool's own file format, not the design or the
# proofs, and cannot be removed from the design. Everything else still fails the run.
abc_notes='(aig: Warning: Treating undriven bit props\.\\clk like \$anyseq\.|aig: Warning: Treating a total of [0-9]+ undriven bits in props like \$anyseq\.|engine_0: Warning: (The last (output is|[0-9]+ outputs are) interpreted as (a )?constraints?\.|The network has no constraints\.))$'

# abc_combinational: the one more message ABC prints, right before it refuses a design without registers ("Error:
# Does not work for combinational networks"). It is accepted only for a proof that formal/run.sh turns into a skip
# for that reason, because the refusal is the answer and there is no verdict to protect.
abc_combinational='engine_0: Warning: The network is combinational\.$'

# scan_warnings <log> [skipped]: records in warnings.txt, and prints on stderr, every line of <log> that has the word
# "warning" (case-insensitive, as a whole word or its plural: ghdl ":warning:", yosys "Warning:", sby "warning").
# A name such as warning_count does not match, because the underscore is part of the word, and the summary
# "Warnings: 0 unique messages, 0 total" of yosys is skipped. The files are scanned after the tool ends, in the
# main shell or in the subshell of prove, so the failure is decided at the end of the run, from warnings.txt.
# The exception of abc_notes applies only to the log of an abc-bmc3 proof (a *.log that is not *.ghdl.log), and
# the one of abc_combinational only when the second argument is "skipped".
scan_warnings() {
  local line ignore='^$^'
  [ "$engine" = abc-bmc3 ] && [[ "$1" == *.log && "$1" != *.ghdl.log ]] && ignore="$abc_notes"
  [ "$engine" = abc-bmc3 ] && [ "${2:-}" = skipped ] && ignore="($ignore|$abc_combinational)"
  { grep -inE '(^|[^[:alnum:]_])warnings?([^[:alnum:]_]|$)' "$1" || true; } \
    | { grep -viE 'warnings?: 0 (unique )?(messages|total)' || true; } \
    | { grep -vE "$ignore" || true; } \
    | while IFS= read -r line; do
        printf 'formal: WARNING treated as error: %s:%s\n' "${1#"$root"/}" "$line" | tee -a "$warnings" >&2
      done
}
