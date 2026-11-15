#!/usr/bin/env bash
# Monta cada fragmento de boot em todas as combinações das macros e confere o disassembly.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
checks=0

# Registra uma verificação; $1 é a condição (0 passa) e $2 a descrição.
expect() {
    checks=$((checks + 1))
    if [ "$1" -ne 0 ]; then
        echo "FALHA: $2"
        failures=$((failures + 1))
    fi
}

# Instruções de cada fragmento com a sua macro e as interrupções ligadas.
declare -A SOLO_COUNT=(
    [Zicsr]=7 [Zicntr]=6 [Zihpm]=89 [Sscofpmf]=31 [Zifencei]=1
)
declare -A SOLO_MACRO=(
    [Zicsr]=RV32_HAS_ZICSR [Zicntr]=RV32_HAS_ZICNTR [Zihpm]=RV32_HAS_ZIHPM
    [Sscofpmf]=RV32_HAS_SSCOFPMF [Zifencei]=RV32_HAS_ZIFENCEI
)

# Monta os fragmentos $2 em diante com as macros $1 (lista "NOME=valor" separada por espaço).
build() {
    local name=$1 macros=$2 march=${MARCH:-rv32i_zicsr_zifencei} abi=${ABI:-ilp32}
    shift 2
    mkdir -p "$work/$name"
    # shellcheck disable=SC2086
    write_config "$work/$name/boot_config.h" $macros
    write_wrapper "$work/$name/wrap.S" "$@"
    assemble "$work/$name/wrap.S" "$work/$name/wrap.o" "$march" "$abi" "$work/$name"
}

# Confere que $1 (.o) só usa x0, x5, x6 e x7, não tem dado nem pilha e só deixa
# indefinido o rv32_boot_trap.
check_object() {
    local object=$1 label=$2 bad symbols
    bad=$(instructions "$object" |
        grep -oE '\bx[0-9]+\b' | grep -vxE 'x0|x5|x6|x7' || true)
    expect "$([ -z "$bad" ]; echo $?)" "$label usa registrador fora de t0 a t2: $bad"
    symbols=$("${CROSS}nm" -a "$object" | grep -vE ' [bdtn] \.(bss|data|text|riscv\.attributes)$' |
        grep -vE '^ +U rv32_boot_trap$' || true)
    expect "$([ -z "$symbols" ]; echo $?)" "$label define ou referencia símbolo: $symbols"
    "${CROSS}size" "$object" | awk 'NR == 2 { exit ($2 != 0 || $3 != 0) }'
    expect "$?" "$label tem dado ou bss"
}

# Cada fragmento sozinho: desligado não gera nada, ligado gera a quantidade esperada.
for fragment in "${BOOT_FRAGMENTS[@]}"; do
    macro=${SOLO_MACRO[$fragment]}
    others=()
    for other in "${BOOT_MACROS[@]}"; do
        [ "$other" != "$macro" ] && others+=("$other=1")
    done
    build "off_$fragment" "${others[*]}" "$fragment"
    expect "$([ "$(text_size "$work/off_$fragment/wrap.o")" -eq 0 ]; echo $?)" \
        "$fragment sem $macro e com as outras macros ligadas gera instrução"
    build "on_$fragment" "$macro=1 RV32_HAS_INTERRUPTS=1" "$fragment"
    expect "$([ "$(text_size "$work/on_$fragment/wrap.o")" -eq $((4 * SOLO_COUNT[$fragment])) ]; echo $?)" \
        "$fragment com $macro não gera ${SOLO_COUNT[$fragment]} instruções"
    check_object "$work/on_$fragment/wrap.o" "$fragment"
done

# O Zicsr sem interrupções não escreve mip, o Sscofpmf sem Zihpm segue a sua macro.
build zicsr_no_irq "RV32_HAS_ZICSR=1" Zicsr
expect "$([ "$(text_size "$work/zicsr_no_irq/wrap.o")" -eq 24 ]; echo $?)" "Zicsr sem interrupções não tem 6 instruções"
expect "$(instructions "$work/zicsr_no_irq/wrap.o" | grep 'csrw.*mip' >/dev/null ; [ $? -ne 0 ]; echo $?)" "Zicsr sem interrupções escreve mip"
build zicsr_irq "RV32_HAS_ZICSR=1 RV32_HAS_INTERRUPTS=1" Zicsr
expect "$(instructions "$work/zicsr_irq/wrap.o" | grep -E 'csrw mip,x0' >/dev/null; echo $?)" "Zicsr com interrupções não zera mip"
build zicsr_af "RV32_HAS_ZICSR=1 RV32_HAS_ACCESS_FAULTS=1" Zicsr
expect "$([ "$(text_size "$work/zicsr_af/wrap.o")" -eq 24 ]; echo $?)" "ACCESS_FAULTS muda o fragmento do Zicsr"

# Todas as combinações válidas das macros das cinco extensões.
combos=0
for bits in $(seq 0 63); do
    zicsr=$((bits & 1)); zicntr=$(((bits >> 1) & 1)); zihpm=$(((bits >> 2) & 1))
    sscof=$(((bits >> 3) & 1)); irq=$(((bits >> 4) & 1)); fencei=$(((bits >> 5) & 1))
    [ $((zicntr | zihpm)) -eq 1 ] && [ "$zicsr" -eq 0 ] && continue
    [ "$sscof" -eq 1 ] && { [ "$zihpm" -eq 0 ] || [ "$irq" -eq 0 ]; } && continue
    combos=$((combos + 1))
    macros="RV32_HAS_ZICSR=$zicsr RV32_HAS_ZICNTR=$zicntr RV32_HAS_ZIHPM=$zihpm RV32_HAS_SSCOFPMF=$sscof"
    macros="$macros RV32_HAS_INTERRUPTS=$irq RV32_HAS_ZIFENCEI=$fencei"
    name="combo_$bits"
    build "$name" "$macros" "${BOOT_FRAGMENTS[@]}"
    # O resultado é a concatenação, na ordem, de cada fragmento montado sozinho.
    : > "$work/$name/expected.txt"
    for fragment in "${BOOT_FRAGMENTS[@]}"; do
        build "${name}_$fragment" "$macros" "$fragment"
        instructions "$work/${name}_$fragment/wrap.o" >> "$work/$name/expected.txt"
    done
    instructions "$work/$name/wrap.o" > "$work/$name/actual.txt"
    cmp -s "$work/$name/expected.txt" "$work/$name/actual.txt"
    expect "$?" "combinação $macros não é a concatenação ordenada dos fragmentos"
    if [ "$fencei" -eq 1 ]; then
        expect "$([ "$(tail -n 1 "$work/$name/actual.txt")" = "fence.i" ]; echo $?)" \
            "fence.i não é a última instrução em $macros"
    else
        expect "$(grep -q 'fence.i' "$work/$name/actual.txt"; [ $? -ne 0 ]; echo $?)" "fence.i sem Zifencei em $macros"
    fi
    check_object "$work/$name/wrap.o" "$macros"
    # As macros das extensões sem estado e as do ambiente não mudam nada.
    build "${name}_extras" "$macros RV32_HAS_M=1 RV32_HAS_ZMMUL=1 RV32_HAS_ZICCLSM=1 RV32_HAS_ZIMOP=1 \
RV32_HAS_ZICOND=1 RV32_HAS_ZIHINTNTL=1 RV32_HAS_ZIHINTPAUSE=1 RV32_HAS_ACCESS_FAULTS=1 RV32_TEST_WAIT=1" \
        "${BOOT_FRAGMENTS[@]}"
    cmp -s "$work/$name/wrap.o" "$work/${name}_extras/wrap.o"
    expect "$?" "macros sem estado mudam a saída em $macros"
    # RV32E: a mesma saída com o -march e o -mabi do RV32E.
    MARCH=rv32e_zicsr_zifencei ABI=ilp32e build "${name}_e" "$macros RV32_IS_E=1" "${BOOT_FRAGMENTS[@]}"
    instructions "$work/${name}_e/wrap.o" | cmp -s - "$work/$name/actual.txt"
    expect "$?" "RV32E gera instruções diferentes em $macros"
done

echo "assemble: $checks verificações em $combos combinações, $failures falhas"
[ "$failures" -eq 0 ]
