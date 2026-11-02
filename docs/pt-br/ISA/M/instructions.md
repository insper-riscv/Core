# Extensão M e Zmmul: Instruções

Capítulo 11 do manual ([M Extension for Integer Multiplication and Division](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)), com a Zmmul na [seção 11.1.3](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html#11-1-3-zmmul-extension-version-1-0).

Este documento reúne o que o manual do RISC-V exige das extensões `M` (multiplicação e divisão inteira) e `Zmmul` (só multiplicação). A fonte é o manual de ISA não privilegiada v20260120, capítulo 11 ("M" Extension for Integer Multiplication and Division, Version 2.0). A implementação no Core está em [description.md](description.md).

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

## 5. Extensão Zmmul (seção 11.1.3)

A `Zmmul` (versão 1.0) contém só o subconjunto de multiplicação da `M`.

| Instrução | Presente na `Zmmul` | Presente na `M` |
| :--- | :--- | :--- |
| `MUL`, `MULH`, `MULHSU`, `MULHU` | Sim | Sim |
| `DIV`, `DIVU`, `REM`, `REMU` | Não | Sim |

As codificações são idênticas às da `M`. A `M` implica a `Zmmul`, de modo que toda implementação da `M` também contém a `Zmmul`. O manual a destina a projetos de baixo custo que precisam multiplicar sem dividir, comuns em microcontroladores e processadores soft core em FPGA, onde o multiplicador costuma ser um bloco dedicado e o divisor é lógica comum.

## 6. Referências

| Capítulo | Seção | Título |
| :--- | :--- | :--- |
| 11 | 11.1 | "M" Extension for Integer Multiplication and Division, Version 2.0 |
| 11 | 11.1.1 | Multiplication Operations |
| 11 | 11.1.2 | Division Operations |
| 11 | 11.1.3 | Zmmul Extension, Version 1.0 |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
