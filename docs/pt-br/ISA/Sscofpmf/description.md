# Sscofpmf no Core

Este documento descreve como o Core implementa a extensão Sscofpmf (estouro de contador e filtragem por modo) para o hart que só tem o modo máquina. A conformidade de cada exigência está em [conformance.md](conformance.md), os contadores de eventos estão em [Zihpm](../Zihpm/description.md) e a tomada de interrupção está em [Zicsr](../Zicsr/description.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Capítulo | 14, "Sscofpmf" Extension for Count Overflow and Mode-Based Filtering, versão 1.0 |
| Fonte | Volume II do manual do RISC-V (ISA privilegiada, versão 20260120), seções 3.1.9, 3.1.10 e 14.1 |
| Conformidade do Core com o volume privilegiado | `docs/conformance/riscv-privilegiado.md` do Insper-RISC-V |

## 2. Parameters

| Parâmetro | Entidade | Padrão | Efeito |
| :--- | :--- | :--- | :--- |
| `HAS_SSCOFPMF` | `core` | `false` | Liga a extensão; exige `HAS_ZIHPM` e `HAS_INTERRUPTS` |

A elaboração falha se `HAS_SSCOFPMF` for ligado sem os outros dois. O perfil da plataforma liga a extensão pelo `extras: [Sscofpmf]` do `platform.yaml`, que o `riscv-tools` traduz em `HAS_SSCOFPMF` no pacote VHDL do mapa de memória. A extensão não faz parte da matriz de perfis do Core, como as interrupções de máquina.

## 3. O que a extensão acrescenta

O Core só tem o modo máquina, então as partes da extensão que dependem dos modos S, U, VS e VU não existem: o campo `SINH`, `UINH`, `VSINH` e `VUINH` do seletor de evento lê zero, e o `scountovf` (`0xDA0`) é um endereço inexistente.

| Item | Posição | Efeito |
| :--- | :--- | :--- |
| `mhpmeventKh` | $0x720 + K$, $K$ de 3 a 31 | Metade alta do seletor de evento do contador $K$ |
| `OF` | Bit 31 de `mhpmeventKh` | Estouro do contador $K$, que só a escrita do programa limpa; com `OF` em `1` um novo estouro não pede interrupção |
| `MINH` | Bit 30 de `mhpmeventKh` | Inibe a contagem de eventos no modo máquina, o único modo do Core |
| `LCOFIP` | Bit 13 de `mip` | Pedido de interrupção de estouro, de leitura e escrita |
| `LCOFIE` | Bit 13 de `mie` | Habilita a interrupção de estouro |
| Causa | `mcause` = `0x8000000D` | Interrupção 13, local de estouro de contador (LCOFI) |

Os demais bits de `mhpmeventKh` leem zero e ignoram a escrita. Um índice sem contador real (`hpm_counters`) lê zero e ignora a escrita em `mhpmeventKh`, sem exceção, como nos outros CSRs do Zihpm. Os endereços `0x720` a `0x722` e `0x740` em diante continuam inexistentes.

## 4. Estouro do contador

O estouro é a soma que leva o contador inteiro de `hpm_width` bits de todos os bits em `1` a zero. Uma escrita no contador ou no seletor nunca estoura. O bloco contador (`counter64`) entrega um pulso `o_wrap` no ciclo seguinte à soma, e o banco do Zihpm trata o pulso assim.

| Situação no pulso | `OF` | `LCOFIP` |
| :--- | :---: | :---: |
| `OF` em `0` | Passa a `1` | Passa a `1` |
| `OF` em `1` | Continua em `1` | Não muda |

O estouro vence uma escrita que limpa `OF` no mesmo ciclo. `LCOFIP` é limpo pelo programa, com uma escrita em `mip` com o bit 13 em `0`, e a escrita em `mip` no ciclo de um pedido não o perde. O bit `OF` também funciona como desabilitação da interrupção do contador, por isso o programa que quer a interrupção limpa `OF` junto com o valor inicial do contador.

O contador estoura de verdade só por uma soma: `mcountinhibit` e `MINH` impedem a soma e, por consequência, o estouro.

## 5. Interrupção

`LCOFIP` e `LCOFIE` entram na condição geral de tomada da seção 7 de [Zicsr](../Zicsr/description.md): a interrupção é tomada com `mstatus.MIE` em `1`, `LCOFIP` e `LCOFIE` em `1`. A prioridade é a do manual, a menor entre as de máquina, depois da externa, da de software e da de timer. No modo vetorado de `mtvec` a interrupção vai a $BASE + 4 \times 13 = BASE + 52$, e o alinhamento de 64 bytes da `BASE` nesse modo comporta a causa 13.

## 6. Estrutura

| Bloco | Papel |
| :--- | :--- |
| `counter64` | Gera o pulso `o_wrap` de estouro |
| `hpm_counter_bank` | Guarda `OF` e `MINH` por contador, aplica `MINH` à contagem e agrega o pedido em `o_ovf_irq` |
| `csr_file` | Decodifica `mhpmeventKh`, guarda `LCOFIP` e `LCOFIE`, e junta o pedido ao `o_irq_pending`, ao `o_irq_take` e ao `o_irq_cause` |

Com `HAS_SSCOFPMF = false` o `csr_file` fixa `LCOFIP` e `LCOFIE` em zero, a faixa `0x720` é inexistente e o banco não instancia `OF` nem `MINH`.

## 7. Verificação

| Garantia | Evidência |
| :--- | :--- |
| Os endereços e o bit 13 existem só com a extensão | Testes `CsrFileSscofpmf`, `CsrFileSscofpmfWide` e `CsrFileSscofpmfOff` |
| O estouro põe `OF` e `LCOFIP` uma vez, com `OF` em `1` não pede, a escrita não estoura, `MINH` impede a contagem, o timer vem antes do estouro | Os mesmos testes e a prova `csr_ofp_props` com oito mutantes |
| O pulso `o_wrap` é o estouro ideal do ciclo anterior, para toda largura | Prova `counter64_props` e os mutantes `wrap_without_hi` e `wrap_on_lo_write` |
| A interrupção é tomada com a causa 13 e vai a `BASE + 52` | Programas `irq-lcofi` e `irq-lcofi-priority` do repositório Tests |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
