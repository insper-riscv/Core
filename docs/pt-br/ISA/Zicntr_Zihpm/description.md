# Zicntr e Zihpm no Core

Este documento descreve como o Core implementa os contadores. O que o manual exige está em [instructions.md](instructions.md), e o banco de CSRs que os hospeda (leitura, escrita atômica, ilegalidade) está em [Zicsr](../Zicsr/description.md).

## 1. Generics

| Generic | Entidade | Padrão | Efeito |
| :--- | :--- | :--- | :--- |
| `has_zicntr` | `core` | `false` | Instancia `mcycle`, `minstret` e `time` com seus espelhos, e o registrador `mcountinhibit`; exige `has_zicsr` |
| `tick_cycles` | `core` | 50 | Ciclos de clock por tick do `time` (50 dá 1 MHz a 50 MHz) |
| `has_zihpm` | `core` | `false` | Instancia os quatro contadores de eventos; exige `has_zicsr` |
| `hpm_counters` | `core` | 0 | Número de contadores de eventos, de 0 a 4; quando maior que 0 prevalece sobre `has_zihpm` |

Com `has_zihpm = true` e `hpm_counters = 0` o Core instancia 4 contadores. A elaboração falha se qualquer um dos genéricos de contador for ligado sem `has_zicsr`.

Cada extensão independe da outra, então o Zihpm funciona sem o Zicntr. O `mcountinhibit` existe quando há `has_zicntr` ou ao menos um contador de eventos.

## 2. Bloco contador de 64 bits

Todo contador é uma instância de `counter64`, que guarda o valor em duas metades de 32 bits.

| Aspecto | Comportamento |
| :--- | :--- |
| Incremento | A metade baixa soma 1 nos ciclos com incremento habilitado |
| Vai-um | Quando a metade baixa estava em $2^{32}-1$, o vai-um fica registrado e a metade alta soma 1 no ciclo seguinte, sem somador de 64 bits no caminho combinacional |
| Leitura | A metade alta lida já inclui o vai-um pendente, então o par lido é sempre o valor ideal de 64 bits |
| Escrita na metade baixa | Substitui o valor e cancela o incremento e o vai-um do mesmo ciclo |
| Escrita na metade alta | Substitui o valor e descarta o vai-um pendente |
| Reset | Zera as duas metades e o vai-um |

Uma escrita vence o incremento do próprio ciclo, em cada metade.

## 3. Contadores do Zicntr

### 3.1. Endereços e regras

Há 3 contadores de 64 bits. O Core não implementa `mcounteren`, e o acesso a esse endereço é ilegal.

| Contador | Metade baixa | Metade alta | Espelho somente leitura (baixa e alta) | Incrementa | Escrita |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `mcycle` | `0xB00` | `0xB80` | `cycle` em `0xC00` e `0xC80` | A cada ciclo de clock, inclusive nos ciclos de parada, salvo inibição | Sim, em cada metade |
| `minstret` | `0xB02` | `0xB82` | `instret` em `0xC02` e `0xC82` | A cada instrução retirada, um ciclo depois da retirada, salvo inibição ou cancelamento | Sim, em cada metade |
| `time` | `0xC01` | `0xC81` | Só existe a forma de leitura | A cada tick do divisor, sem inibição | Não |

Os endereços `0xB01` e `0xB81` não existem, e o `time` não tem forma de máquina. Escrever efetivamente em `cycle`, `instret` ou `time` é acesso ilegal (`mcause = 2`). Sem `has_zicntr` os endereços de contador são inexistentes e o acesso é ilegal.

### 3.2. Retirada de instruções

A instrução em EX é retirada quando é válida, o pipeline anda e não há exceção. O pulso de retirada fica pendente por um ciclo, de modo que uma exceção de load ou store tomada em MEM o cancele, e o acesso que falha não conta em `minstret`.

| Situação | Efeito em `minstret` |
| :--- | :--- |
| Retirada pendente | A leitura de `minstret` e `instret` já soma a retirada pendente, e a soma efetiva ocorre no ciclo seguinte |
| Exceção de MEM no ciclo seguinte | A retirada é cancelada e não conta |
| Escrita em `minstret` no mesmo ciclo | A retirada da própria instrução de escrita é descartada |
| Instrução que causa exceção em EX | Não gera pulso de retirada |

### 3.3. Divisor de tick e `time`

O `time` soma 1 a cada pulso do divisor de tick. O divisor conta de 0 a $tick\_cycles - 1$, emite o pulso no ciclo em que a contagem chega ao fim e volta a 0 no ciclo seguinte. O reset zera a contagem.

$$f_{time} = \frac{f_{clock}}{tick\_cycles}$$

O Core não tem entrada externa de tempo. O `time` deriva do clock do próprio Core, e a resolução é fixada por `tick_cycles` (no mínimo 1).

## 4. `mcountinhibit`

O registrador `mcountinhibit` fica em `0x320`. Seus bits que aceitam escrita dependem do que o perfil inclui, e os demais leem zero e ignoram escrita.

| Bit | Inibe | Existe quando |
| :--- | :--- | :--- |
| 0 | `mcycle` | `has_zicntr` |
| 1 | Nada (o `time` não é inibível) | Nunca |
| 2 | `minstret` | `has_zicntr` |
| $3+k$ | O contador de eventos de índice $3+k$ | $k < N$, com $N$ contadores |

Um contador inibido mantém o valor e continua legível e gravável. A inibição de `minstret` também suspende a soma da retirada pendente que a leitura mostra.

## 5. Contadores de eventos do Zihpm

### 5.1. Organização

Com $N$ contadores (de 1 a 4), o Core implementa os contadores de índices 3 a $2+N$. Cada contador de índice $K$ tem quatro endereços de contador e um seletor de evento.

| CSR | Endereço | Escrita |
| :--- | :--- | :--- |
| `mhpmeventK` | $0x320 + K$ | Sim, guarda um código de 4 bits (os bits superiores leem zero) |
| `mhpmcounterK` | $0xB00 + K$ | Sim |
| `mhpmcounterKh` | $0xB80 + K$ | Sim |
| `hpmcounterK` | $0xC00 + K$ | Não |
| `hpmcounterKh` | $0xC80 + K$ | Não |

Os índices de 3 a 31 que o Core não implementa dão acesso ilegal, como qualquer endereço inexistente. Escrever em `hpmcounterK` ou `hpmcounterKh` é acesso ilegal. Cada contador usa o bloco de 64 bits da Seção 2, e o código do evento é zerado no reset.

### 5.2. Regra de contagem

Um contador soma 1 em cada ciclo em que o bit do vetor de eventos escolhido pelo código vale `'1'`, o código não é zero e o bit de inibição do contador vale `'0'`. Um código fora da tabela de eventos não conta.

### 5.3. Tabela de eventos

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

## 6. Endereço inexistente

O banco de CSRs trata como inexistente todo endereço de contador cuja extensão ou índice o perfil não inclui. Ler ou escrever nele sinaliza acesso CSR ilegal, que o Core trata como exceção de instrução ilegal (`mcause = 2`). Não há valor constante de retorno. O mesmo vale para a escrita efetiva em qualquer espelho de leitura.

## 7. Verificação formal

| Prova | Arquivo | O que garante |
| :--- | :--- | :--- |
| `counter64` | `formal/counter64_props.sv` | O par de metades é sempre o valor ideal de 64 bits, a escrita vence o incremento, o vai-um nunca se perde e o valor não decresce sem escrita (indução, cover) |
| `csr_file` com Zicntr | `formal/csr_cntr_props.sv` | Valores lidos de `mcycle`, `minstret` e espelhos, escrita por metade, espelhos e `time` somente leitura, bits 0 e 2 de `mcountinhibit` e cancelamento de retirada (BMC de 6 ciclos, cover) |
| `csr_file` com Zihpm | `formal/csr_hpm_props.sv` | Seleção de evento, inibição, escrita por metade, espelhos somente leitura e endereços ilegais dos contadores ausentes, com 4 contadores e com 2 contadores junto de Zicntr (BMC de 6 ciclos, cover) |

O procedimento das provas está em [FORMAL.md](../../FORMAL.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
