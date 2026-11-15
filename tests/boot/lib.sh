#!/usr/bin/env bash
# Funções comuns dos testes dos fragmentos de boot (tests/boot).

# Todas as macros que boot_config.h define, na ordem em que o Tools as escreve.
BOOT_MACROS=(
    RV32_HAS_M RV32_HAS_ZMMUL RV32_HAS_ZICSR RV32_HAS_ZICNTR RV32_HAS_ZIHPM
    RV32_HAS_ZIFENCEI RV32_HAS_ZICCLSM RV32_HAS_ZIMOP RV32_HAS_ZICOND
    RV32_HAS_ZIHINTNTL RV32_HAS_ZIHINTPAUSE RV32_HAS_INTERRUPTS
    RV32_HAS_SSCOFPMF RV32_HAS_ACCESS_FAULTS RV32_IS_E RV32_TEST_WAIT
)

# Fragmentos na ordem fixa de inclusão do contrato.
BOOT_FRAGMENTS=(Zicsr Zicntr Zihpm Sscofpmf Zifencei)

# Raiz do repositório do Core, a partir da pasta deste arquivo.
CORE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# Prefixo das ferramentas do toolchain RISC-V.
CROSS=${CROSS:-riscv32-unknown-elf-}

# Escreve o boot_config.h de $1 com todas as macros em 0 e as "NOME=valor" seguintes.
write_config() {
    local file=$1 macro pair
    shift
    declare -A value=()
    for macro in "${BOOT_MACROS[@]}"; do value[$macro]=0; done
    for pair in "$@"; do value[${pair%%=*}]=${pair#*=}; done
    {
        echo "#ifndef RV32_BOOT_CONFIG_H"
        echo "#define RV32_BOOT_CONFIG_H"
        for macro in "${BOOT_MACROS[@]}"; do echo "#define $macro ${value[$macro]}"; done
        echo "#endif"
    } > "$file"
}

# Escreve em $1 um .S que inclui boot_config.h e os fragmentos $2 em diante.
write_wrapper() {
    local file=$1 fragment
    shift
    {
        echo '#include "boot_config.h"'
        for fragment in "$@"; do echo "#include \"$fragment/boot.inc\""; done
    } > "$file"
}

# Monta $1 (.S) em $2 (.o) com o -march $3 e o -mabi $4, procurando boot_config.h em $5.
assemble() {
    "${CROSS}gcc" -c -x assembler-with-cpp -nostdlib -march="$3" -mabi="$4" \
        -I"$5" -I"$CORE_ROOT/src" "$1" -o "$2"
}

# Lista as instruções de $1 (.o), só o texto da instrução, sem endereço nem codificação.
instructions() {
    "${CROSS}objdump" -d -M numeric "$1" | awk -F'\t' 'NF >= 3 { line = $3; for (i = 4; i <= NF; i++) line = line " " $i; print line }'
}

# Diz o tamanho em bytes da seção de texto de $1 (.o).
text_size() {
    "${CROSS}size" "$1" | awk 'NR == 2 { print $1 }'
}
