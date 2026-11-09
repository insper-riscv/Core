#!/usr/bin/env bash
# Escreve o config_pkg de uma variante de formal/configs.yaml: o pacote padrão do Common-Components com as
# constantes da variante trocadas. Uso, na raiz do repositório:  bash formal/config_variant.sh <nome> <arquivo>
set -euo pipefail

name="${1:?nome da variante}"
out="${2:?arquivo de saída}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default="$root/src/common/src/config_pkg.vhd"

line="$(sed -n "s/^$name: *//p" "$root/formal/configs.yaml")"
[ -n "$line" ] || { echo "variante '$name' ausente em formal/configs.yaml" >&2; exit 1; }

mkdir -p "$(dirname "$out")"
cp "$default" "$out"
for item in $line; do
  key="${item%%=*}"
  val="${item#*=}"
  case "$val" in
    true|false) new="$val" ;;
    0x*) new="$(printf 'resize(unsigned'"'"'(x"%08X"), ADDR_BITS + 1)' "$val")" ;;
    *) new="$val" ;;
  esac
  sed -i -E "s/^(\tconstant $key +: +[a-z_]+ +:= ).*;\$/\1${new//&/\\&};/" "$out"
done
cmp -s "$default" "$out" && { echo "variante '$name': nenhuma constante mudou o pacote" >&2; exit 1; }
exit 0
