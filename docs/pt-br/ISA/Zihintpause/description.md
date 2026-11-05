# Zihintpause: Implementação no Core

Este documento descreve como o Core executa a dica `pause`. A codificação está em [instructions.md](instructions.md).

## 1. Configuração

| Genérico | Padrão | Efeito |
| :--- | :--- | :--- |
| `has_zihintpause` | `false` | Instancia no estágio ID o decodificador que reconhece `pause` |

A palavra de `pause` é um `FENCE` válido, então o núcleo a executa como `nop` com o genérico ligado ou desligado. Ligado, o estágio ID a identifica como dica e desabilita a escrita em `rd`.

## 2. Decodificação no Estágio ID

O decodificador reivindica exatamente a palavra `0x0100000F`, ou seja, `opcode = 0001111`, `funct3 = 000`, `rd` e `rs1` em `x0`, `fm = 0000`, `pred = 0001` e `succ = 0000`. As demais formas de `FENCE` não são reivindicadas.

O pipeline é em ordem e de um único fio de execução, então não há outro fio a quem ceder recursos, e `pause` não insere espera.

## 3. Verificação

| Nível | Cobertura |
| :--- | :--- |
| Entidade `zihintpause_decode` | A palavra do manual, a inversão de cada um dos 32 bits e outras formas de `FENCE`, que deixam de ser reivindicadas |
| Núcleo | `pause` em sequência com as demais dicas, sem alteração de registrador e sem exceção |
| Formal | O decodificador reivindica exatamente uma palavra, com três mutantes rejeitados |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
