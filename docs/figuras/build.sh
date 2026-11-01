#!/usr/bin/env bash
# Compila cada .tex da pasta (exceto o estilo compartilhado) em PDF e converte para SVG ao lado do fonte.
set -euo pipefail

cd "$(dirname "$0")"

for fonte in *.tex; do
  [[ "$fonte" == estilo.tex ]] && continue
  base="${fonte%.tex}"
  latexmk -pdf -interaction=nonstopmode "$fonte"
  dvisvgm --no-fonts --pdf "$base.pdf" --output="$base.svg"
  latexmk -c "$fonte"
  rm -f "$base.pdf"
done
