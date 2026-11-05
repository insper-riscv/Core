# Zihintpause: Instruções

Capítulo 13 do manual ([Zihintpause Extension for Pause Hint, Version 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zihintpause.html)).

Este documento reúne o que o manual do RISC-V exige da extensão `Zihintpause`. A implementação no Core está em [description.md](description.md).

## 1. Visão Geral

A `Zihintpause` define a dica `pause`, que sugere à implementação reduzir a taxa de instruções do fio de execução por um curto período, como em laços de espera ativa. Por ser uma dica (HINT), pode ser executada como `nop`, sem efeito arquitetural e sem exceção.

## 2. Codificação

`pause` é um `FENCE` com `fm = 0000`, `pred = 0001` (escrita), `succ = 0000`, `rs1 = x0` e `rd = x0`.

| Instrução | Bits [31:20] | Bits [19:15] | Bits [14:12] | Bits [11:7] | Bits [6:0] | Palavra |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `pause` | `0000 0001 0000` | `00000` | `000` | `00000` | `0001111` | `0x0100000F` |

## 3. Semântica

| Aspecto | Comportamento |
| :--- | :--- |
| Registradores | Nenhum é alterado |
| Memória | Nenhum acesso |
| Exceção de instrução ilegal | Nunca ocorre |

## 4. Referências

| Capítulo | Título |
| :--- | :--- |
| 13 | "Zihintpause" Extension for Pause Hint, Version 2.0 |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
