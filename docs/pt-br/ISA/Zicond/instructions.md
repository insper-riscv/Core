# Zicond: Instruções

Capítulo 10 do manual ([Zicond Extension for Integer Conditional Operations, Version 1.0.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicond.html)).

Este documento reúne o que o manual do RISC-V exige da extensão `Zicond`. A fonte é o manual de ISA não privilegiada v20260120, capítulo 10, seção 10.1. A implementação no Core está em [description.md](description.md).

## 1. Visão Geral

As duas instruções são do formato R-type e usam o `opcode` das operações entre registradores. Cada uma lê `rs1` e `rs2`, escreve o resultado de 32 bits em `rd` e não gera exceção. No RV32, `XLEN` vale 32.

| Campo | Bits | Valor |
| :--- | :--- | :--- |
| `opcode` | [6:0] | `0110011` |
| `funct7` | [31:25] | `0000111` |
| `funct3` | [14:12] | `101` (`czero.eqz`) ou `111` (`czero.nez`) |

## 2. Semântica (seção 10.1.1)

| Instrução | Condição sobre `rs2` | `rd` |
| :--- | :--- | :--- |
| `czero.eqz rd, rs1, rs2` | $rs2 = 0$ | $0$ |
| `czero.eqz rd, rs1, rs2` | $rs2 \ne 0$ | $rs1$ |
| `czero.nez rd, rs1, rs2` | $rs2 \ne 0$ | $0$ |
| `czero.nez rd, rs1, rs2` | $rs2 = 0$ | $rs1$ |

A condição olha o valor inteiro de 32 bits de `rs2`: um único bit em 1, em qualquer posição, o torna diferente de zero. Quando `rd` é `x0` a escrita é descartada, como em qualquer instrução, e quando `rs1` é `x0` o resultado é sempre zero.

## 3. Sequências de Uso (seção 10.1.2)

O manual compõe operações condicionais a partir das duas instruções, com `rc` como registrador de condição.

| Operação | Sequência |
| :--- | :--- |
| Soma condicional se zero | `czero.nez rd, rs2, rc` e `add rd, rs1, rd` |
| Seleção condicional se zero | `czero.nez rd, rs1, rc`, `czero.eqz rtmp, rs2, rc` e `add rd, rd, rtmp` |
| E condicional se zero | `and rd, rs1, rs2`, `czero.eqz rtmp, rs1, rc` e `or rd, rd, rtmp` |

A subtração, o OU e o OU exclusivo condicionais seguem a forma da soma, trocando `add` pela instrução correspondente. A versão "se diferente de zero" troca `czero.nez` por `czero.eqz`.

## 4. Referências

| Capítulo | Seção | Título |
| :--- | :--- | :--- |
| 10 | 10.1 | "Zicond" Extension for Integer Conditional Operations, Version 1.0.0 |
| 10 | 10.1.1 | Instructions (czero.eqz e czero.nez) |
| 10 | 10.1.2 | Usage examples |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
