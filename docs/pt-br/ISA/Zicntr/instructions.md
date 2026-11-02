# Zicntr, o que o manual exige

Capítulo 6 do manual ([Zicntr and Zihpm Extensions for Counters](https://docs.riscv.org/reference/isa/v20260120/unpriv/counters.html)).

Este documento resume o que o manual de ISA não privilegiada (versão 20260120) exige da extensão Zicntr. A fonte é o Capítulo 6, "Zicntr and Zihpm Extensions for Counters, Version 2.0", seção 6.1.1, e o texto abaixo é uma paráfrase. O capítulo define também o Zihpm, descrito em [Zihpm](../Zihpm/instructions.md). Como o Core implementa cada ponto está em [description.md](description.md), e o acesso aos CSRs em si (`CSRRW`, `CSRRS`, `CSRRC` e variantes) está em [Zicsr](../Zicsr/instructions.md).

## 1. Visão geral (Capítulo 6, Seção 6.1.1)

A extensão dá acesso, do nível não privilegiado, a três contadores de 64 bits. Cada contador é lido por um CSR somente leitura de `XLEN` bits, nos endereços $0xC00$ a $0xC02$. No RV32 (`XLEN = 32`) as metades altas ficam nos endereços $0xC80$ a $0xC82$. A extensão depende do Zicsr.

## 2. Zicntr, contadores básicos (Seção 6.1.1)
### 2.1. Os três contadores

| CSR (metade baixa) | CSR (metade alta, RV32) | O que mede |
| :--- | :--- | :--- |
| `cycle` | `cycleh` | Ciclos de execução do núcleo |
| `time` | `timeh` | Tempo de relógio de parede |
| `instret` | `instreth` | Instruções retiradas pelo hart |

Os endereços individuais são $0xC00$, $0xC01$ e $0xC02$ para as metades baixas e $0xC80$, $0xC81$ e $0xC82$ para as altas.

Regras do manual para cada contador:

1. `cycle` conta ciclos do núcleo. O comportamento durante o estado de espera (sleep) depende do ambiente de execução.
2. `time` conta o tempo de relógio de parede. Os harts de um sistema precisam estar sincronizados a menos de um tick, e o software precisa observar `time` sempre não decrescente. O período do tick é definido pelo ambiente de execução.
3. `instret` conta as instruções retiradas pelo hart. Uma instrução que causa exceção síncrona, inclusive `ECALL` e `EBREAK`, não incrementa o contador.

### 2.2. Largura e leitura no RV32

Os contadores têm 64 bits mesmo quando `XLEN = 32`, de modo que o software consegue detectar o estouro. No RV32 a leitura de 64 bits usa duas instruções de CSR, uma por metade. Para obter um valor coerente mesmo que a metade baixa estoure entre as duas leituras, o manual mostra uma sequência de três leituras.

1. Ler a metade alta (`cycleh`).
2. Ler a metade baixa (`cycle`).
3. Ler a metade alta de novo e repetir tudo se as duas leituras da metade alta diferirem.

### 2.3. Acesso

Os CSRs de contador são somente leitura no nível não privilegiado, e uma escrita efetiva neles é uma tentativa de escrita em CSR somente leitura (regra do Zicsr). O manual permite que um ambiente de execução proíba o acesso aos contadores, por exemplo para dificultar ataques de canal lateral de temporização.

## 3. Fora do escopo deste capítulo

O capítulo não define os CSRs de máquina que controlam os contadores básicos, como `mcycle`, `minstret` e `mcountinhibit`. Esses registradores pertencem ao manual de arquitetura privilegiada, que não foi consultado para este documento. A descrição do que o Core oferece nesses endereços está em [description.md](description.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
