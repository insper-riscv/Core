#!/usr/bin/env bash
# Escreve o config_pkg de uma variante: o pacote padrão do Common-Components com as constantes da variante
# trocadas (CONFIG_BASE aponta outro pacote de partida). A variante é uma chave de formal/configs.yaml ou, com --set, a própria lista CONSTANTE=valor
# (a mesma de uma linha do configs.yaml, entre aspas). Uso, na raiz do repositório:
#   bash formal/config_variant.sh <nome> <arquivo>
#   bash formal/config_variant.sh --set "HAS_ZICSR=true HAS_M=false" <arquivo>
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default="${CONFIG_BASE:-$root/src/common/src/config_pkg.vhd}"

if [ "${1:-}" = "--set" ]; then
  line="${2-}"
  out="${3:?arquivo de saída}"
  name="--set"
else
  name="${1:?nome da variante}"
  out="${2:?arquivo de saída}"
  line="$(sed -n "s/^$name: *//p" "$root/formal/configs.yaml")"
  [ -n "$line" ] || { echo "variante '$name' ausente em formal/configs.yaml" >&2; exit 1; }
fi

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
  grep -qE "^[[:space:]]+constant $key +:" "$out" || { echo "constante '$key' ausente no config_pkg" >&2; exit 1; }
  sed -i -E "s/^([[:space:]]+constant $key +: +[a-z_]+ +:= ).*;\$/\1${new//&/\\&};/" "$out"
done
[ "$name" = "--set" ] || ! cmp -s "$default" "$out" || { echo "variante '$name': nenhuma constante mudou o pacote" >&2; exit 1; }
exit 0
