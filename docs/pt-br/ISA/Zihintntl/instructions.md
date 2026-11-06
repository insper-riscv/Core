# Zihintntl: Instruções

Capítulo 7 do manual ([Zihintntl Extension for Non-Temporal Locality Hints, Version 1.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zihintntl.html)).

Este documento reúne o que o manual do RISC-V exige da extensão `Zihintntl`. A implementação no Core está em [description.md](description.md).

## 1. Visão Geral

A `Zihintntl` define quatro dicas de localidade não temporal. Cada uma informa à implementação que o acesso à memória da instrução seguinte não tem localidade temporal em um dos domínios de cache. Como toda dica (HINT) do RISC-V, ela pode ser ignorada, e uma implementação que a ignora a executa como `nop`, sem efeito arquitetural e sem exceção.

## 2. Codificação

As dicas são `ADD` com `rd = x0` e `rs1 = x0`. O registrador `rs2` escolhe o domínio.

| Instrução | Equivale a | Palavra |
| :--- | :--- | :--- |
| `ntl.p1` | `add x0, x0, x2` | `0x00200033` |
| `ntl.pall` | `add x0, x0, x3` | `0x00300033` |
| `ntl.s1` | `add x0, x0, x4` | `0x00400033` |
| `ntl.all` | `add x0, x0, x5` | `0x00500033` |

As formas comprimidas (`c.ntl.*`) pertencem à extensão `C`, que o Core não implementa.

## 3. Semântica

| Aspecto | Comportamento |
| :--- | :--- |
| Registradores | Nenhum é alterado, pois a escrita em `x0` é descartada |
| Memória | Nenhum acesso |
| Exceção de instrução ilegal | Nunca ocorre |

## 4. Referências

| Capítulo | Título |
| :--- | :--- |
| 12 | "Zihintntl" Extension for Non-Temporal Locality Hints, Version 1.0 |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
