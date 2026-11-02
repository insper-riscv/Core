# Banco de 16 Registradores (RV32E)

O genérico `num_regs` do `core` escolhe quantos registradores de uso geral o processador tem. Com 32, o padrão, ele é um RV32I. Com 16, ele é um RV32E, que troca os registradores `x16` a `x31` por menos área. As exigências do manual estão em [instructions.md](instructions.md).

## 1. O Que Muda

| Item | `num_regs = 32` | `num_regs = 16` |
| :--- | :--- | :--- |
| Registradores | `x0` a `x31` | `x0` a `x15` |
| Endereço do `reg_file` | 5 bits | 4 bits |
| Instrução com `x16` a `x31` | Executa | Ilegal, causa 2 do `mcause` com `has_zicsr` |
| Bit de base do `misa` com `has_zicsr` | `I` (bit 8) | `E` (bit 4), e o bit `I` fica em zero |

O `misa` segue o manual privilegiado ([seção 2.1.1.1](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#misa)), que liga o bit `E` na RV32E e define que ele lê como o complemento do bit `I`. Só os valores 16 e 32 são aceitos, e outro valor para a elaboração com erro. O estágio ID calcula a largura do endereço do banco como o número de bits necessário para indexar `num_regs` registradores e liga ao banco apenas esses bits baixos dos índices `rs1`, `rs2` e `rd`.

## 2. Instrução Ilegal

O manual reserva as codificações com `x16` a `x31` (seção 2.1.2), e o Core as trata como instrução ilegal. No RV32E o bit mais alto de cada campo de registrador que a instrução usa precisa ser zero. O estágio ID confere os três campos pela forma da instrução.

| Campo | Instruções que o usam |
| :--- | :--- |
| `rd` | LUI, AUIPC, JAL, JALR, loads, operações com imediato, operações entre registradores e instruções CSR |
| `rs1` | JALR, desvios, loads, stores, operações com imediato, operações entre registradores e CSR com registrador |
| `rs2` | Desvios, stores e operações entre registradores |

Uma instrução ilegal não escreve nenhum registrador e segue a mesma via de exceção de qualquer outra instrução ilegal. Os campos que a instrução não usa, como o `rs2` de um load, não são conferidos.

### 2.1. Destino da Exceção

| Configuração | Efeito |
| :--- | :--- |
| Com `has_zicsr` | Trap síncrono com causa 2 (instrução ilegal) registrada no `mcause` |
| Sem `has_zicsr` | Pulso de um ciclo na saída de trap do `core`, com a causa no formato do `mcause` e o PC da instrução |

## 3. Compatibilidade

O banco menor não muda o pipeline nem o adiantamento, que seguem comparando índices de 5 bits. Como a verificação de ilegalidade só depende de `num_regs`, ela é independente das demais extensões, e as 60 combinações de extensões de `profiles/matrix.yaml` valem tanto para a base de 32 registradores quanto para a de 16, o que dá 120 perfis.

Os programas do RV32E usam a ABI `ilp32e`, definida na especificação psABI do RISC-V (fora do manual de ISA), que só aloca registradores até `x15`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
