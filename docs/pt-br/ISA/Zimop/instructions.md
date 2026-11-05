# Zimop: Instruções

Capítulo 9 do manual, seção 9.1 ([Zimop Extension for May-Be-Operations, Version 1.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zimop.html)).

Este documento reúne o que o manual do RISC-V exige da extensão `Zimop`. A fonte é o manual de ISA não privilegiada v20260120, capítulo 9, seção 9.1. A implementação no Core está em [description.md](description.md).

## 1. Visão Geral

A `Zimop` reserva 40 codificações da classe `SYSTEM` como operações possivelmente definidas (May-Be-Operations, MOPs). Uma extensão futura pode atribuir um significado a cada uma. Enquanto isso, a MOP escreve zero em `rd`, em vez de não fazer nada, o que simplifica a decodificação e permite ao software detectar a extensão: um programa que executa a MOP e encontra um valor diferente de zero em `rd` sabe que outra extensão a redefiniu.

Uma MOP nunca causa exceção de instrução ilegal quando a `Zimop` está presente. Isso permite que um mesmo binário rode com ou sem a extensão que redefine a MOP, e é o motivo de a `Zimop` existir como extensão à parte.

## 2. Codificação

As duas famílias usam o `opcode` `1110011` (`SYSTEM`) e o `funct3` `100`. Os bits de `n` ficam espalhados pela palavra, como mostra a tabela.

| Instrução | Valores de `n` | Bits [31:25] | Bits [24:20] | Bits [19:15] | Bits [14:12] | Bits [11:7] | Bits [6:0] |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `mop.r.n rd, rs1` | 0 a 31 (32 instruções) | `1 n[4] 00 n[3:2] 0` | `111 n[1:0]` | `rs1` | `100` | `rd` | `1110011` |
| `mop.rr.n rd, rs1, rs2` | 0 a 7 (8 instruções) | `1 n[2] 00 n[1:0] 1` | `rs2` | `rs1` | `100` | `rd` | `1110011` |

As palavras de referência são `0x81C04073` para `mop.r.0` e `0x82004073` para `mop.rr.0`, com `rd`, `rs1` e `rs2` iguais a `x0`.

## 3. Semântica

$$
x[rd] \leftarrow 0
$$

| Aspecto | Comportamento |
| :--- | :--- |
| Valor escrito | Zero, em `rd`, para as 40 codificações |
| Leitura de `rs1` e `rs2` | O valor lido não influencia o resultado |
| `rd = x0` | Nenhuma escrita, como em qualquer instrução |
| Exceção de instrução ilegal | Nunca ocorre com a extensão presente |

## 4. Referências

| Capítulo | Seção | Título |
| :--- | :--- | :--- |
| 9 | 9.1 | "Zimop" Extension for May-Be-Operations, Version 1.0 |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
