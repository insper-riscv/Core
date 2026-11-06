# Perfis do Core

Um perfil é uma combinação de extensões do RISC-V que o `core` implementa, escolhida pelos genéricos de entrada. Este documento descreve os arquivos que definem os perfis, as regras que geram a matriz completa e os perfis de referência mantidos em `profiles/`.

## 1. Arquivos

| Arquivo | Conteúdo |
| :--- | :--- |
| `profiles/matrix.yaml` | As bases (RV32I e RV32E), as extensões com o genérico que liga cada uma e as regras entre elas |
| `profiles/<perfil>.yaml` | Um perfil de referência, com `extensions`, `top`, `generics` e a lista `sources` em ordem de dependência do GHDL |
| `paths.yaml` | Seção `provides` com as fontes de cada componente de `src/` e as dependências entre componentes |

## 2. Matriz

A matriz é a fonte única dos perfis válidos. O comando `riscv-tools profiles --spec profiles/matrix.yaml` a expande em 480 perfis, e o alvo `profile-matrix` do `Makefile` elabora cada um com os genéricos correspondentes.

### 2.1. Bases e extensões

| Item | Genérico | Observação |
| :--- | :--- | :--- |
| RV32I | `has_e => false` | Base com 32 registradores |
| RV32E | `has_e => true` | Base com 16 registradores |
| Zicclsm | `has_zicclsm` | Acessos desalinhados tratados no hardware |
| Zicsr | `has_zicsr` | Banco de CSRs e traps |
| Zicntr | `has_zicntr` | Implica Zicsr |
| Zihpm | `has_zihpm` | Implica Zicsr; parametrizado por `hpm_counters` e `hpm_width` |
| Zifencei | `has_zifencei` | Instrução `FENCE.I` |
| Zimop | `has_zimop` | As 40 codificações `mop.r.n` e `mop.rr.n` |
| Zicond | `has_zicond` | `czero.eqz` e `czero.nez` |
| Zmmul | `has_zmmul` | Multiplicação sem divisão |
| M | `has_m` | Multiplicação e divisão; implica Zmmul |

### 2.2. Regras entre extensões

| Regra | Efeito |
| :--- | :--- |
| M e Zmmul são mutuamente exclusivas | O nome do perfil traz só uma das duas |
| Zicsr é exclusiva com Zicntr e com Zihpm | Os contadores são CSRs, então o nome do perfil com um deles não cita Zicsr |
| Zicntr e Zihpm podem coexistir | O nome traz `zicntr_zihpm` |

### 2.3. Nome do perfil

O nome começa pela base (`rv32i` ou `rv32e`), com `m` anexado direto quando M está ligada, e depois dos nomes das demais extensões em minúsculas, na ordem da lista `extensions` de `matrix.yaml`. Um perfil de teste fora dos nomes gerados leva o sufixo `_reduced`.

## 3. Perfis de referência

| Perfil | Extensões | Genéricos além dos de extensão |
| :--- | :--- | :--- |
| `rv32i` | I | `has_m => false` |
| `rv32i_zmmul` | I, Zmmul | |
| `rv32im` | I, M | |
| `rv32im_zicsr` | I, M, Zicsr | |
| `rv32im_zicsr_zifencei` | I, M, Zicsr, Zifencei | |
| `rv32im_zicclsm_zicntr_zifencei` | I, M, Zicclsm, Zicntr, Zifencei | |
| `rv32im_zicclsm_zicntr_zihpm_zifencei` | I, M, Zicclsm, Zicntr, Zihpm, Zifencei | `hpm_counters => 29`, `hpm_width => 64` |
| `rv32im_zicclsm_zicntr_zihpm_zifencei_reduced` | as mesmas | `hpm_counters => 4`, `hpm_width => 40` |
| `rv32im_zimop` | I, M, Zimop | |
| `rv32im_zicond` | I, M, Zicond | |

Todos os perfis de referência têm `top: core` e analisam as mesmas unidades de extensão que o `core` instancia diretamente. As unidades desligadas por genérico saem da elaboração quando as instruções `generate` são avaliadas, então a lista `sources` não muda com o genérico.

## 4. Componentes de `src/`

A seção `provides` de `paths.yaml` divide `src/` em componentes, um por pasta, mais o componente `constants`, que reúne os pacotes de constantes de todas as pastas porque os decodificadores e as unidades de uma pasta leem as constantes das outras.

| Componente | Depende de |
| :--- | :--- |
| `constants` | nenhum |
| `shared`, `I-E`, `M`, `Zicclsm`, `Zicntr`, `Zicond`, `Zifencei`, `Zimop` | `constants` |
| `Zihpm` | `constants`, `Zicntr` |
| `Zicsr` | `constants`, `Zicntr`, `Zihpm` |
| `core` | todos os anteriores |

Cada componente declara em `requires` os blocos de `src/common/` (submódulo Common-Components) que usa, no formato `Common-Components/<componente>`, e `riscv-tools sources core` os resolve no manifesto do submódulo. A ordem das fontes dentro de cada componente é a ordem de dependência do GHDL, e o `check-paths` confere que cada arquivo listado existe.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
