#!/usr/bin/env bash
# Roda os fragmentos de boot no Spike com o estado sujo e confere o estado que deixam.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPIKE=${SPIKE:-spike}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
runs=0

# Monta e roda uma configuração; $1 é o nome, $2 o -march do montador, $3 o -mabi,
# $4 o --isa do Spike e $5 em diante as macros "NOME=valor" de boot_config.h.
run_case() {
    local name=$1 march=$2 abi=$3 isa=$4 status=0
    shift 4
    runs=$((runs + 1))
    mkdir -p "$work/$name"
    write_config "$work/$name/boot_config.h" "$@"
    assemble "$CORE_ROOT/tests/boot/check.S" "$work/$name/check.o" "$march" "$abi" "$work/$name"
    "${CROSS}ld" -m elf32lriscv -T "$CORE_ROOT/tests/boot/link.ld" "$work/$name/check.o" -o "$work/$name/check.elf"
    timeout 120 "$SPIKE" --isa="$isa" --disable-dtb -m0x80000000:0x100000 "$work/$name/check.elf" \
        > "$work/$name/spike.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        echo "FALHA: $name (--isa=$isa), código de saída $status (ver a tabela de códigos do contrato de boot)"
        tail -n 5 "$work/$name/spike.log"
        failures=$((failures + 1))
    fi
}

run_case nenhuma rv32i_zicsr_zifencei ilp32 rv32i_zicsr_zifencei
run_case zicsr rv32i_zicsr_zifencei ilp32 rv32i_zicsr RV32_HAS_ZICSR=1
run_case zicsr_irq rv32i_zicsr_zifencei ilp32 rv32i_zicsr RV32_HAS_ZICSR=1 RV32_HAS_INTERRUPTS=1
run_case zicsr_af rv32i_zicsr_zifencei ilp32 rv32i_zicsr RV32_HAS_ZICSR=1 RV32_HAS_ACCESS_FAULTS=1
run_case zicntr_fencei rv32i_zicsr_zifencei ilp32 rv32i_zicsr_zicntr_zifencei \
    RV32_HAS_ZICSR=1 RV32_HAS_ZICNTR=1 RV32_HAS_ZIFENCEI=1
run_case zihpm rv32i_zicsr_zifencei ilp32 rv32i_zicsr_zihpm RV32_HAS_ZICSR=1 RV32_HAS_ZIHPM=1
run_case completo rv32i_zicsr_zifencei ilp32 rv32i_zicsr_zicntr_zihpm_sscofpmf_zifencei \
    RV32_HAS_ZICSR=1 RV32_HAS_ZICNTR=1 RV32_HAS_ZIHPM=1 RV32_HAS_SSCOFPMF=1 RV32_HAS_INTERRUPTS=1 RV32_HAS_ZIFENCEI=1 \
    RV32_HAS_M=1 RV32_HAS_ZICCLSM=1 RV32_HAS_ZICOND=1 RV32_HAS_ZIMOP=1
# Cada fragmento sozinho, sem o Zicsr limpar o mip antes, com a ISA completa no Spike.
full_isa=rv32i_zicsr_zicntr_zihpm_sscofpmf_zifencei
run_case so_sscofpmf rv32i_zicsr_zifencei ilp32 "$full_isa" RV32_HAS_SSCOFPMF=1
run_case so_zihpm rv32i_zicsr_zifencei ilp32 "$full_isa" RV32_HAS_ZIHPM=1
run_case so_zicntr rv32i_zicsr_zifencei ilp32 "$full_isa" RV32_HAS_ZICNTR=1
run_case so_zifencei rv32i_zicsr_zifencei ilp32 "$full_isa" RV32_HAS_ZIFENCEI=1
run_case rv32e rv32e_zicsr_zifencei ilp32e rv32e_zicsr_zicntr_zihpm_zifencei \
    RV32_HAS_ZICSR=1 RV32_HAS_ZICNTR=1 RV32_HAS_ZIHPM=1 RV32_HAS_ZIFENCEI=1 RV32_IS_E=1

echo "spike: $runs configurações, $failures falhas"
[ "$failures" -eq 0 ]
