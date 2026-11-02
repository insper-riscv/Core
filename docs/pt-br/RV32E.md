# Banco de 16 Registradores (RV32E)

O genérico `num_regs` do `core` escolhe quantos registradores de uso geral o processador tem. Com 32, o padrão, ele é um RV32I. Com 16, ele é um RV32E, que troca os registradores `x16` a `x31` por menos área.

## 1. O Que Muda

| Item | `num_regs = 32` | `num_regs = 16` |
| :--- | :--- | :--- |
| Registradores | `x0` a `x31` | `x0` a `x15` |
| Endereço do `reg_file` | 5 bits | 4 bits |
| Instrução com `x16` a `x31` | Executa | Ilegal, causa 2 do `mcause` com `has_zicsr` |

Só os valores 16 e 32 são aceitos, e outro valor para a elaboração com erro.

## 2. Instrução Ilegal

No RV32E o bit mais alto de cada campo de registrador que a instrução usa precisa ser zero. O estágio ID confere os três campos pela forma da instrução.

| Campo | Instruções que o usam |
| :--- | :--- |
| `rd` | LUI, AUIPC, JAL, JALR, loads, operações com imediato, operações entre registradores e instruções CSR |
| `rs1` | JALR, desvios, loads, stores, operações com imediato, operações entre registradores e CSR com registrador |
| `rs2` | Desvios, stores e operações entre registradores |

Uma instrução ilegal não escreve nenhum registrador e segue a mesma via de exceção de qualquer outra instrução ilegal. Os campos que a instrução não usa, como o `rs2` de um load, não são conferidos.

## 3. Compatibilidade

O banco menor não muda o pipeline nem o adiantamento, que seguem comparando índices de 5 bits. Os programas do RV32E usam a ABI `ilp32e`, que só aloca registradores até `x15`.
