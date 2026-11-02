# Zihpm no Core

Este documento descreve como o Core implementa os contadores de eventos do Zihpm. O que o manual exige está em [instructions.md](instructions.md), o bloco contador de 64 bits e o `time` estão em [Zicntr](../Zicntr/description.md), e o banco de CSRs que os hospeda (leitura, escrita atômica, ilegalidade) está em [Zicsr](../Zicsr/description.md).

## 1. Generics

| Generic | Entidade | Padrão | Efeito |
| :--- | :--- | :--- | :--- |
| `has_zihpm` | `core` | `false` | Instancia os quatro contadores de eventos; exige `has_zicsr` |
| `hpm_counters` | `core` | 0 | Número de contadores de eventos, de 0 a 4; quando maior que 0 prevalece sobre `has_zihpm` |

Com `has_zihpm = true` e `hpm_counters = 0` o Core instancia 4 contadores. A elaboração falha se qualquer um dos genéricos de contador for ligado sem `has_zicsr`. O Zihpm independe do Zicntr e funciona sem ele.

## 2. Organização

Com $N$ contadores (de 1 a 4), o Core implementa os contadores de índices 3 a $2+N$. Cada contador de índice $K$ tem quatro endereços de contador e um seletor de evento.

| CSR | Endereço | Escrita |
| :--- | :--- | :--- |
| `mhpmeventK` | $0x320 + K$ | Sim, guarda um código de 4 bits (os bits superiores leem zero) |
| `mhpmcounterK` | $0xB00 + K$ | Sim |
| `mhpmcounterKh` | $0xB80 + K$ | Sim |
| `hpmcounterK` | $0xC00 + K$ | Não |
| `hpmcounterKh` | $0xC80 + K$ | Não |

Os índices de 3 a 31 que o Core não implementa dão acesso ilegal, como qualquer endereço inexistente. Escrever em `hpmcounterK` ou `hpmcounterKh` é acesso ilegal. Cada contador usa o bloco de 64 bits descrito em [Zicntr](../Zicntr/description.md), e o código do evento é zerado no reset.

## 3. Regra de contagem

Um contador soma 1 em cada ciclo em que o bit do vetor de eventos escolhido pelo código vale `'1'`, o código não é zero e o bit de inibição do contador vale `'0'`. Um código fora da tabela de eventos não conta.

## 4. Tabela de eventos

O vetor de eventos tem 16 bits, um por código, e o bit 0 é sempre zero.

| Código | Evento | Condição de contagem | Origem |
| :---: | :--- | :--- | :--- |
| 0 | Nenhum | Nunca conta | Não se aplica |
| 1 | Parada da multiplicação ou divisão | Ciclo em que a unidade M segura o pipeline | Core |
| 2 | Espera por memória externa | Ciclo em que um acesso à RAM externa aguarda o sinal de pronto | Core |
| 3 | Desvio ou salto tomado | Desvio condicional com condição verdadeira, `JAL` ou `JALR`, com o pipeline andando | Core |
| 4 | Acesso desalinhado | Primeiro ciclo de um acesso desalinhado executado em duas etapas | Core |
| 5 | Falha da cache de instruções | Pulso da cache de instruções, no bit 0 da entrada externa de eventos | Fora do Core |
| 6 | Falha da cache de dados | Pulso da cache de dados, no bit 1 da entrada externa de eventos | Fora do Core |
| 7 | Espera por FLASH | Ciclo de espera por FLASH, no bit 2 da entrada externa de eventos | Fora do Core |
| 8 | Parada por dependência de load | Ciclo em que a detecção de load-use segura o fetch sem outra parada ativa | Core |
| 9 | Operação fundida | Ciclo em que a unidade M conclui uma operação reaproveitando o resultado da anterior | Core |
| 10 a 15 | Reservados | Nunca contam | Não se aplica |

O evento 9 conta a fusão de pares de multiplicação ou divisão (por exemplo `MULH` seguido de `MUL` com os mesmos operandos), descrita em [M](../M/description.md). Os eventos 5 a 7 só contam se o SoC ligar a entrada externa de eventos do Core, que por padrão vale zero.

## 5. `mcountinhibit`

O registrador `mcountinhibit` fica em `0x320`, e os bits de `mcycle` e `minstret` estão em [Zicntr](../Zicntr/description.md). Os bits dos contadores de eventos dependem de quantos o perfil inclui, e os demais leem zero e ignoram escrita.

| Bit | Inibe | Existe quando |
| :--- | :--- | :--- |
| $3+k$ | O contador de eventos de índice $3+k$ | $k < N$, com $N$ contadores |

Um contador inibido mantém o valor e continua legível e gravável.

## 6. Endereço inexistente

O banco de CSRs trata como inexistente todo endereço de contador de desempenho cujo índice o perfil não inclui. Ler ou escrever nele sinaliza acesso CSR ilegal, que o Core trata como exceção de instrução ilegal (`mcause = 2`). Não há valor constante de retorno. O mesmo vale para a escrita efetiva em `hpmcounterK` e `hpmcounterKh`.

## 7. Verificação formal

| Prova | Arquivo | O que garante |
| :--- | :--- | :--- |
| `csr_file` com Zihpm | `formal/csr_hpm_props.sv` | Seleção de evento, inibição, escrita por metade, espelhos somente leitura e endereços ilegais dos contadores ausentes, com 4 contadores e com 2 contadores junto de Zicntr (BMC de 6 ciclos, cover) |

O procedimento das provas está em [FORMAL.md](../../FORMAL.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
