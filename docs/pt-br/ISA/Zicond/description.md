# Zicond: Implementação no Core

Este documento descreve como o Core executa as instruções da `Zicond`. O que o manual exige está em [instructions.md](instructions.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Capítulo | 10, Zicond Extension for Integer Conditional Operations, versão 1.0.0 |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), numeração sem a Introdução |
| Requisitos do manual | [instructions.md](instructions.md) |

## 2. Configuração

| Genérico | Padrão | Efeito |
| :--- | :--- | :--- |
| `has_zicond` | `false` | Instancia o decodificador no estágio ID e a unidade de execução no estágio EX |

Com `has_zicond = false`, as duas codificações não são reivindicadas por nenhum decodificador, e a unidade de controle as marca como instruções ilegais, como qualquer codificação fora do RV32I. O perfil `rv32im_zicond` liga o genérico para a compilação no GHDL.

## 3. Decodificação no Estágio ID

O decodificador reivindica a instrução quando os três campos da tabela abaixo coincidem, qualquer que seja o valor de `rd`, `rs1` e `rs2`.

| Campo | Valor |
| :--- | :--- |
| `opcode` | `0110011` |
| `funct7` | `0000111` |
| `funct3` | `101` ou `111` |

Para uma instrução reivindicada, o decodificador habilita a escrita em `rd`, seleciona `rs1` como operando A e remove o sinal de instrução ilegal. Ele entrega ao estágio EX um código de operação de 5 bits no campo que já carrega a operação da ULA, com um código para cada instrução.

| Instrução | Código de operação |
| :--- | :--- |
| `czero.eqz` | `01100` |
| `czero.nez` | `01110` |

Nenhum dos dois códigos é de uma operação da ULA, então o estágio EX distingue as instruções sem um sinal novo no registrador ID/EX. A seleção do resultado da ULA continua a de uma soma, e esse resultado não é usado.

## 4. Execução no Estágio EX

A unidade de execução é combinacional e recebe $rs1$ e $rs2$ depois do adiantamento, de modo que lê o valor produzido por uma instrução anterior ainda no pipeline. Com $c$ valendo 1 quando $rs2 = 0$, o resultado é dado abaixo.

$$
rd = \begin{cases}
0 & \text{se } (\texttt{czero.eqz} \land c) \lor (\texttt{czero.nez} \land \lnot c) \\
rs1 & \text{caso contrário}
\end{cases}
$$

O resultado entra no multiplexador de resultado do estágio EX, que o escolhe quando o código de operação é o de uma das duas instruções. Dali segue pelo caminho comum de uma instrução aritmética: adiantamento para as instruções seguintes e escrita em `rd` no estágio WB. A instrução leva um ciclo no estágio EX e não para o pipeline.

## 5. Verificação

| Verificação | O que cobre |
| :--- | :--- |
| Teste de entidade do decodificador | As duas codificações, a independência dos campos de registrador e as codificações vizinhas que não são reivindicadas |
| Teste de entidade da unidade de execução | A tabela de verdade, cada um dos 32 bits de `rs1` e de `rs2`, operandos pseudoaleatórios e os códigos de operação da ULA que não são reivindicados |
| Teste do núcleo com `has_zicond` | `rs2` igual e diferente de zero, `rd` igual a `rs1`, `rd` igual a `x0`, `rs1` igual a `x0`, `rs1` e `rs2` no mesmo registrador e o adiantamento do operando e do resultado |
| Teste do núcleo sem `has_zicond` | As duas instruções geram a exceção de instrução ilegal (causa 2) |
| Provas formais | A semântica da tabela da seção 2 de [instructions.md](instructions.md) e a exatidão da codificação reivindicada, cada propriedade com mutantes do VHDL que precisam ser pegos |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
