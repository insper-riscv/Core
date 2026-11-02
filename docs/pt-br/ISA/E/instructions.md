# RV32E: Conjunto Base de Instruções Inteiras Reduzido

Capítulo 2 do manual ([RV32E and RV64E Base Integer Instruction Sets](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32e.html)).

Este documento resume o que o manual do RISC-V exige da base RV32E. A fonte é o manual de ISA não privilegiada (v20260120), Capítulo 2, "RV32E and RV64E Base Integer Instruction Sets, Version 2.0", seção 2.1 e subseções. O capítulo só descreve as diferenças para a base RV32I e deve ser lido depois do Capítulo 1 ("RV32I Base Integer Instruction Set, Version 2.1"). A implementação no Core está em [description.md](description.md).

## 1. Finalidade (seção 2.1)

O manual define a RV32E como uma versão reduzida da RV32I, voltada a microcontroladores embarcados, cuja única mudança é reduzir o número de registradores inteiros para 16. As extensões padrão compatíveis com a RV32I também são compatíveis com a RV32E, salvo indicação em contrário.

## 2. Modelo de Programação (seção 2.1.1)

| Item | RV32I | RV32E |
| :--- | :--- | :--- |
| Registradores inteiros de uso geral | `x0` a `x31` | `x0` a `x15` |
| `x0` | Fixo em zero | Fixo em zero |

O manual justifica a redução pela área, pois em implementações pequenas da RV32I os 16 registradores superiores ocupam cerca de um quarto da área do núcleo sem contar as memórias. Retirá-los economiza cerca de 25% dessa área, com redução proporcional de potência.

## 3. Codificação (seção 2.1.2)

As instruções da RV32E têm as mesmas codificações da RV32I, com a diferença de que só `x0` a `x15` existem. O manual declara como reservadas todas as codificações que especificam `x16` a `x31`.

| Aspecto | Exigência do manual |
| :--- | :--- |
| Formatos e opcodes | Idênticos aos da RV32I |
| Campos `rd`, `rs1` e `rs2` | Só podem nomear `x0` a `x15` |
| Codificações com `x16` a `x31` | Reservadas, para uso futuro em espaço custom ou em novas codificações padrão |

O manual não define o comportamento de hardware diante de uma codificação reservada nesta seção, e a escolha de tratá-la como instrução ilegal pertence à implementação (ver [description.md](description.md)).

## 4. Limites do Capítulo

O Capítulo 2 não trata de convenção de chamada (ABI), de instruções HINT nem de CSRs. A ABI da RV32E (`ilp32e`) vem da especificação psABI do RISC-V, fora do manual de ISA não privilegiada, e este documento não descreve seus detalhes.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
