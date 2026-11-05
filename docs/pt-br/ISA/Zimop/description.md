# Zimop: Implementação no Core

Este documento descreve como o Core executa as 40 instruções da `Zimop`. O que o manual exige, com as codificações, está em [instructions.md](instructions.md).

## 1. Configuração

| Genérico | Padrão | Efeito |
| :--- | :--- | :--- |
| `has_zimop` | `false` | Instancia o decodificador no estágio ID e passa a executar `mop.r.n` e `mop.rr.n` |

Com `has_zimop = false`, o decodificador não existe na elaboração e as 40 codificações seguem o caminho de qualquer instrução `SYSTEM` não suportada. Com `has_zicsr = true`, isso gera exceção de instrução ilegal (causa 2), e sem `has_zicsr` o sinal de exceção do núcleo sobe. O restante do núcleo não muda com a extensão ligada ou desligada.

## 2. Decodificação no Estágio ID

O decodificador reivindica uma palavra quando ela satisfaz uma das condições da tabela. Os campos `rd`, `rs1` e `rs2` e os bits de `n` não entram na decisão.

| Família | Condição sobre a palavra |
| :--- | :--- |
| `mop.r.n` | `opcode = 1110011`, `funct3 = 100`, bit 31 em 1, bits [29:28] em zero, bit 25 em zero e bits [24:22] em um |
| `mop.rr.n` | `opcode = 1110011`, `funct3 = 100`, bit 31 em 1, bits [29:28] em zero e bit 25 em 1 |

Uma palavra reivindicada ativa a escrita em `rd` e substitui dois sinais que seguem para os estágios seguintes.

| Sinal | Valor para uma MOP | Motivo |
| :--- | :--- | :--- |
| Operação da ULA | Operação de desvio `BGEU`, que não seleciona nenhum resultado de dados | O resultado da ULA vale zero |
| `opcode` apresentado ao estágio EX | O de uma instrução aritmética com imediato | A unidade de exceções e o banco de CSRs não tratam a palavra como `SYSTEM` |

O desvio `BGEU` só decide um desvio quando o `opcode` é o de desvios condicionais, e o `opcode` apresentado a EX é outro, então a MOP nunca altera o fluxo de controle.

## 3. Caminho de Dados

O zero percorre o mesmo caminho do resultado de uma instrução aritmética. Ele atravessa os registradores de barreira `EX/MEM` e `MEM/WB`, é adiantado às instruções seguintes pela unidade de `forwarding` e é gravado em `rd` no estágio WB. Uma MOP seguida de uma instrução que lê `rd` fornece zero a essa instrução sem parada. A escrita em `x0` é descartada pelo banco de registradores, como em qualquer instrução.

## 4. Interações

| Item | Comportamento |
| :--- | :--- |
| RV32E | O bit 4 de `rd` em um torna a instrução ilegal, como em qualquer instrução que escreve `rd` |
| Zicsr | Nenhum CSR é lido nem escrito, e nenhuma exceção é gerada |
| Hazard de load | A MOP é tratada como leitora de `rs1`, então um `load` imediatamente anterior ao mesmo registrador causa um ciclo de parada |

## 5. Verificação

| Nível | Cobertura |
| :--- | :--- |
| Entidade `zimop_decode` | As 32 codificações de `mop.r.n` e as 8 de `mop.rr.n` com vários `rd`, `rs1` e `rs2`, e a inversão de cada bit fixo, que deixa de ser reivindicada |
| Núcleo | As 40 codificações com destino sujo, `rd = rs1` e `rd = x0`, sem exceção registrada |
| Formal | O decodificador reivindica exatamente as 40 famílias, escreve `rd` e entrega a operação sem resultado de dados, com sete mutantes rejeitados |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
