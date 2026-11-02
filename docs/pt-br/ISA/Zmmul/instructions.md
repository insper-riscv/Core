# Zmmul: Instruções

Capítulo 11 do manual, seção 11.1.3 ([Zmmul Extension, Version 1.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html#11-1-3-zmmul-extension-version-1-0)).

Este documento reúne o que o manual do RISC-V exige da extensão `Zmmul`, que contém só o subconjunto de multiplicação da `M`. A fonte é o manual de ISA não privilegiada v20260120, capítulo 11, seção 11.1.3. A divisão, que a `Zmmul` não inclui, está em [M](../M/instructions.md). A implementação no Core está em [description.md](description.md).

## 1. Visão Geral

As instruções são do formato R-type e usam o `opcode` `0110011` das operações entre registradores e o `funct7` `0000001`, os mesmos da `M`. O bit 2 do `funct3` vale zero nas quatro instruções.

## 2. Codificação

| Instrução | `funct3` | Grupo | Seção do manual |
| :--- | :--- | :--- | :--- |
| `MUL` | `000` | Multiplicação | 11.1.1 |
| `MULH` | `001` | Multiplicação | 11.1.1 |
| `MULHSU` | `010` | Multiplicação | 11.1.1 |
| `MULHU` | `011` | Multiplicação | 11.1.1 |


## 3. Multiplicação (seção 11.1.1)

O produto completo de dois operandos de 32 bits tem 64 bits. Cada instrução devolve uma metade dele.

| Instrução | Interpretação de `rs1` | Interpretação de `rs2` | Resultado |
| :--- | :--- | :--- | :--- |
| `MUL` | Complemento de dois | Complemento de dois | Bits [31:0] do produto |
| `MULH` | Com sinal | Com sinal | Bits [63:32] do produto |
| `MULHSU` | Com sinal | Sem sinal | Bits [63:32] do produto |
| `MULHU` | Sem sinal | Sem sinal | Bits [63:32] do produto |

Os 32 bits baixos são iguais para qualquer interpretação dos operandos, por isso `MUL` não tem versão por sinal. O `MULHSU` serve à multiplicação com sinal de várias palavras.

### 3.1. Obtenção do Produto Completo

Para obter as duas metades, o manual manda emitir `MULH[[S]U] rdh, rs1, rs2` seguido de `MUL rdl, rs1, rs2`, com os operandos de origem na mesma ordem e com `rdh` diferente de `rs1` e `rs2`. A microarquitetura pode fundir a sequência numa única multiplicação.

## 4. Relação com a M (seção 11.1.3)

A `Zmmul` (versão 1.0) contém só o subconjunto de multiplicação da `M`.

| Instrução | Presente na `Zmmul` | Presente na `M` |
| :--- | :--- | :--- |
| `MUL`, `MULH`, `MULHSU`, `MULHU` | Sim | Sim |
| `DIV`, `DIVU`, `REM`, `REMU` | Não | Sim |

As codificações são idênticas às da `M`. A `M` implica a `Zmmul`, de modo que toda implementação da `M` também contém a `Zmmul`. O manual a destina a projetos de baixo custo que precisam multiplicar sem dividir, comuns em microcontroladores e processadores soft core em FPGA, onde o multiplicador costuma ser um bloco dedicado e o divisor é lógica comum.

## 5. Referências

| Capítulo | Seção | Título |
| :--- | :--- | :--- |
| 11 | 11.1.1 | Multiplication Operations |
| 11 | 11.1.3 | Zmmul Extension, Version 1.0 |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
