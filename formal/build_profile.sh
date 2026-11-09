#!/usr/bin/env bash
# Analisa e elabora o core de um perfil: o config_pkg padrão do Common-Components com as constantes do perfil trocadas
# (formal/config_variant.sh --set) ocupa o lugar dele na lista de fontes, e os genéricos que sobram (hpm_counters e
# hpm_width) vão ao GHDL. Com QUIET definido a linha de sucesso não é impressa. Uso, na raiz do repositório:
#   bash formal/build_profile.sh <nome> <pasta> "<CONSTANTE=valor ...>" "<-gnome=valor ...>" <fonte.vhd>...
set -euo pipefail

name="${1:?nome do perfil}"
dir="${2:?pasta de trabalho}"
sets="${3-}"
gens="${4-}"
shift 4
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "$dir"
mkdir -p "$dir"
bash "$root/formal/config_variant.sh" --set "$sets" "$dir/config_pkg.vhd"

files=()
for f in "$@"; do
  if [ "$f" = "src/common/src/config_pkg.vhd" ]; then f="$dir/config_pkg.vhd"; fi
  files+=("$f")
done
ghdl -a --std=08 --workdir="$dir" "${files[@]}"
# shellcheck disable=SC2086
ghdl --elab-run --std=08 --workdir="$dir" -o "$dir/core" core $gens --stop-time=1ns > "$dir/run.log" 2>&1 \
  && { [ -n "${QUIET:-}" ] || echo "profile $name builds ($sets $gens)"; } || { echo "profile $name FAILED ($sets $gens)"; cat "$dir/run.log"; exit 1; }
