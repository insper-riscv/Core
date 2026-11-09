# Zihintntl: Implementação no Core

Este documento descreve como o Core executa as quatro dicas da `Zihintntl`. As codificações estão em [instructions.md](instructions.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Capítulo | 7, Zihintntl Extension for Non-Temporal Locality Hints, versão 1.0 |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), numeração sem a Introdução |
| Requisitos do manual | [instructions.md](instructions.md) |

## 2. Configuração

| Constante | Padrão | Efeito |
| :--- | :--- | :--- |
| `HAS_ZIHINTNTL` | `false` | Instancia no estágio ID o decodificador que reconhece as quatro dicas |

Uma dica é um `ADD` válido em `x0`, então o núcleo a executa como `nop` com o genérico ligado ou desligado. A diferença é que, ligado, o estágio ID identifica a palavra como dica e desabilita a escrita em `rd`, de modo que nenhum registrador de destino chega aos estágios seguintes.

## 3. Decodificação no Estágio ID

O decodificador reivindica uma palavra quando todas as condições da tabela valem.

| Campo | Valor |
| :--- | :--- |
| `opcode` | `0110011` |
| `funct3` | `000` |
| `funct7` | `0000000` |
| `rd` e `rs1` | `x0` |
| `rs2` | `x2` a `x5` |

Uma palavra reivindicada não habilita a escrita em `rd`. O Core não tem hierarquia de cache com domínios de localidade, então a dica não altera mais nada.

## 4. Verificação

| Nível | Cobertura |
| :--- | :--- |
| Entidade `zihintntl_decode` | As quatro palavras do manual, todos os valores de `rs2` e a inversão de cada bit fixo, que deixa de ser reivindicada |
| Núcleo | As cinco dicas (com `pause`) em sequência, com os registradores lidos logo depois, sem alteração de registrador e sem exceção |
| Formal | O decodificador reivindica exatamente as quatro codificações, com cinco mutantes rejeitados |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
