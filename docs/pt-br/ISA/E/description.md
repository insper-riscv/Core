# Banco de 16 Registradores (RV32E)

A constante booleana `IS_E` do `config_pkg` escolhe quantos registradores de uso geral o processador tem. Falso, o padrão, dá um RV32I de 32 registradores. Verdadeiro dá um RV32E, que troca os registradores `x16` a `x31` por menos área. As exigências do manual estão em [instructions.md](instructions.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Capítulo | 2, RV32E and RV64E Base Integer Instruction Sets, versão 2.0 |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), numeração sem a Introdução |
| Requisitos do manual | [instructions.md](instructions.md) |

## 2. O Que Muda

| Item | `IS_E = false` | `IS_E = true` |
| :--- | :--- | :--- |
| Registradores | `x0` a `x31` | `x0` a `x15` |
| Índice de registrador depois do estágio ID (`reg_t`) | 5 bits | 4 bits |
| Instrução com `x16` a `x31` | Executa | Ilegal, causa 2 do `mcause` com `HAS_ZICSR` |
| Bit de base do `misa` com `HAS_ZICSR` | `I` (bit 8) | `E` (bit 4), e o bit `I` fica em zero |

O `misa` segue o manual privilegiado ([seção 2.1.1.1](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#misa)), que liga o bit `E` na RV32E e define que ele lê como o complemento do bit `I`. O estágio ID calcula a largura do endereço do banco (5 bits com `IS_E` falso, 4 bits com `IS_E` verdadeiro) e liga ao banco apenas esses bits baixos dos índices `rs1`, `rs2` e `rd`.

## 3. Instrução Ilegal

O manual reserva as codificações com `x16` a `x31` (seção 2.1.2), e o Core as trata como instrução ilegal. No RV32E o bit mais alto de cada campo de registrador que a instrução usa precisa ser zero. O estágio ID confere os três campos pela forma da instrução.

| Campo | Instruções que o usam |
| :--- | :--- |
| `rd` | LUI, AUIPC, JAL, JALR, loads, operações com imediato, operações entre registradores e instruções CSR |
| `rs1` | JALR, desvios, loads, stores, operações com imediato, operações entre registradores e CSR com registrador |
| `rs2` | Desvios, stores e operações entre registradores |

Uma instrução ilegal não escreve nenhum registrador e segue a mesma via de exceção de qualquer outra instrução ilegal. Os campos que a instrução não usa, como o `rs2` de um load, não são conferidos.

### 3.1. Destino da Exceção

| Configuração | Efeito |
| :--- | :--- |
| Com `HAS_ZICSR` | Trap síncrono com causa 2 (instrução ilegal) registrada no `mcause` |
| Sem `HAS_ZICSR` | Pulso de um ciclo na saída de trap do `core`, com a causa no formato do `mcause` e o PC da instrução |

## 4. Compatibilidade

O estágio ID converte o campo de 5 bits da instrução (`reg_field_t`) no índice `reg_t` de `REG_BITS` bits, junto da checagem que recusa `x16` a `x31`. O adiantamento, a dependência de load, os registradores EX/MEM e MEM/WB e o write-back carregam `reg_t`. O campo de 5 bits fica só onde é codificação: os campos `rs1` e `rd` que chegam ao estágio EX (o imediato de 5 bits das instruções CSR e a checagem de `ECALL`, `EBREAK`, `MRET` e `WFI`) e os decodificadores. Como a verificação de ilegalidade só depende de `IS_E`, ela é independente das demais extensões, e as 60 combinações de extensões de `profiles/matrix.yaml` valem tanto para a base de 32 registradores quanto para a de 16, o que dá 120 perfis.

Os programas do RV32E usam a ABI `ilp32e`, definida na [psABI do RISC-V](https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/v1.0/riscv-cc.adoc#ilp32e-calling-convention) (fora do manual de ISA), que só aloca registradores até `x15`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
