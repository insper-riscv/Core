# Zmmul: Implementação no Core

Este documento descreve como o Core executa as instruções da `Zmmul`. O que o manual exige está em [instructions.md](instructions.md). O decodificador, a unidade de execução, a parada do pipeline e a fusão de pares são compartilhados com a `M` e estão em [M](../M/description.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Capítulo | 11, M Extension, seção 11.1.3 (Zmmul, versão 1.0) |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), numeração sem a Introdução |
| Requisitos do manual | [instructions.md](instructions.md) |

## 2. Configuração

| Constante | Padrão | Efeito |
| :--- | :--- | :--- |
| `HAS_ZMMUL` | `false` | Instancia o decodificador e o multiplicador, sem o divisor (4 instruções) |

O divisor só é instanciado com `HAS_M`, de modo que `HAS_ZMMUL = true` com `HAS_M = false` dá o perfil sem divisão. Os perfis válidos nunca combinam as duas extensões (ver o [README](../../../../README.md)).

## 3. Decodificação sem Divisão

O parâmetro de divisão do decodificador recebe o valor de `HAS_M`. Sem divisão, só os `funct3` com o bit 2 em zero são reivindicados, ou seja, as quatro multiplicações. Uma instrução com `funct7 = 0000001` e `funct3` de divisão não é reivindicada, e a unidade de controle a marca como ilegal. O restante da decodificação está em [M](../M/description.md).

## 4. Multiplicador de Booth Radix-2

O multiplicador faz a multiplicação com sinal de 32 por 32 bits e produz o produto de 64 bits. Mantém um acumulador de 33 bits, o multiplicador de 32 bits, um bit auxiliar à direita e o multiplicando estendido com sinal para 33 bits. A cada passo examina o par formado pelo bit menos significativo do multiplicador e pelo bit auxiliar.

| Par | Operação sobre o acumulador |
| :--- | :--- |
| `01` | Soma o multiplicando |
| `10` | Subtrai o multiplicando |
| `00` ou `11` | Mantém o acumulador |

Em seguida o conjunto é deslocado um bit à direita, de forma aritmética. Após 32 passos, o acumulador e o multiplicador formam as metades alta e baixa do produto. A latência é de 33 ciclos (1 de inicialização e 32 passos), e a faixa com sinal inclui $-2^{31}$.

A metade baixa vale para qualquer interpretação de sinal. A metade alta sai interpretada como com sinal nos dois operandos, e a `multdiv` a corrige para os modos sem sinal com dois somadores de 32 bits.

$$
\text{alta}_{\text{corrigida}} = \text{alta} + (A_{31} \land \neg s_A) \cdot B + (B_{31} \land \neg s_B) \cdot A \pmod{2^{32}}
$$

Nessa expressão, $s_A$ e $s_B$ valem 1 quando o respectivo operando tem sinal. Para `MULH` a correção é nula, para `MULHSU` só vale o termo que soma $A$ e para `MULHU` valem os dois termos.

## 5. Parada do Pipeline

A multiplicação tem latência de 33 ciclos na unidade, e o pipeline para por 35, porque a parada cobre também o estado de término e o ciclo em que o resultado é capturado. A lógica de parada e o custo das demais operações estão em [M](../M/description.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
