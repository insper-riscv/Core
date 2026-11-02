# Extensão M: Instruções

Capítulo 11 do manual ([M Extension for Integer Multiplication and Division](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)).

Este documento reúne o que o manual do RISC-V exige da extensão `M` (multiplicação e divisão inteira). A fonte é o manual de ISA não privilegiada v20260120, capítulo 11 ("M" Extension for Integer Multiplication and Division, Version 2.0). A `M` implica a `Zmmul`, que contém as quatro instruções de multiplicação e está descrita em [Zmmul](../Zmmul/instructions.md). A implementação no Core está em [description.md](description.md).

## 1. Visão Geral

Todas as instruções são do formato R-type e compartilham o `opcode` de operações entre registradores e o valor de `funct7` que identifica a extensão; só o `funct3` distingue a operação.

| Campo | Bits | Valor |
| :--- | :--- | :--- |
| `opcode` | [6:0] | `0110011` |
| `funct7` | [31:25] | `0000001` |
| `funct3` | [14:12] | Seleciona a operação (seção 2) |

Os operandos são `rs1` e `rs2`, e o resultado de 32 bits vai para `rd`. No RV32, `XLEN` vale 32.

## 2. Codificação

| Instrução | `funct3` | Grupo | Seção do manual |
| :--- | :--- | :--- | :--- |
| `MUL` | `000` | Multiplicação | 11.1.1 |
| `MULH` | `001` | Multiplicação | 11.1.1 |
| `MULHSU` | `010` | Multiplicação | 11.1.1 |
| `MULHU` | `011` | Multiplicação | 11.1.1 |
| `DIV` | `100` | Divisão | 11.1.2 |
| `DIVU` | `101` | Divisão | 11.1.2 |
| `REM` | `110` | Divisão | 11.1.2 |
| `REMU` | `111` | Divisão | 11.1.2 |

O bit 2 do `funct3` separa os dois grupos, e nas divisões o bit 0 separa a versão com sinal da sem sinal.

## 3. Multiplicação (seção 11.1.1)

As quatro instruções de multiplicação (`MUL`, `MULH`, `MULHSU` e `MULHU`) são as da `Zmmul`. A semântica delas e a sequência que obtém o produto completo estão em [Zmmul](../Zmmul/instructions.md).

## 4. Divisão (seção 11.1.2)

| Instrução | Operandos | Resultado |
| :--- | :--- | :--- |
| `DIV` | Com sinal | Quociente de `rs1` por `rs2`, arredondado em direção a zero |
| `DIVU` | Sem sinal | Quociente de `rs1` por `rs2`, arredondado em direção a zero |
| `REM` | Com sinal | Resto da divisão, com o mesmo sinal do dividendo quando não nulo |
| `REMU` | Sem sinal | Resto da divisão |

Salvo o estouro, vale a identidade abaixo para dividendo $n$, divisor $d$, quociente $q$ e resto $r$.

$$
n = d \cdot q + r
$$

### 4.1. Casos Especiais

O manual (tabela 1 da seção 11.1.2) define o resultado sem gerar exceção.

| Condição | Quociente (`DIV`, `DIVU`) | Resto (`REM`, `REMU`) |
| :--- | :--- | :--- |
| Divisão por zero | Todos os bits em 1 (`0xFFFFFFFF`) | Igual ao dividendo |
| Estouro com sinal ($-2^{31} \div -1$) | Igual ao dividendo ($-2^{31}$) | $0$ |

A divisão sem sinal não estoura. O manual justifica o quociente de bits em 1 por ser o maior valor sem sinal, produzido naturalmente pelos divisores sem sinal simples, e rejeita a exceção na divisão por zero porque ela seria a única operação aritmética da ISA a gerar trap.

### 4.2. Obtenção de Quociente e Resto

Para obter os dois, o manual manda emitir `DIV[U] rdq, rs1, rs2` seguido de `REM[U] rdr, rs1, rs2`, com `rdq` diferente de `rs1` e `rs2`. A microarquitetura pode fundir a sequência numa única divisão.

## 5. Referências

| Capítulo | Seção | Título |
| :--- | :--- | :--- |
| 11 | 11.1 | "M" Extension for Integer Multiplication and Division, Version 2.0 |
| 11 | 11.1.1 | Multiplication Operations |
| 11 | 11.1.2 | Division Operations |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
