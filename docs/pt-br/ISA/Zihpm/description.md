# Zihpm no Core

Este documento descreve como o Core implementa os contadores de eventos do Zihpm. O que o manual exige está em [instructions.md](instructions.md), a conformidade de cada exigência está em [conformance.md](conformance.md), o bloco contador e o `time` estão em [Zicntr](../Zicntr/description.md), e o banco de CSRs que hospeda os contadores (leitura, escrita atômica, ilegalidade) está em [Zicsr](../Zicsr/description.md).

## 1. Generics

| Generic | Entidade | Padrão | Efeito |
| :--- | :--- | :--- | :--- |
| `has_zihpm` | `core` | `false` | Liga a extensão: os 29 endereços de cada faixa passam a existir; exige `has_zicsr` |
| `hpm_counters` | `core` | 29 | Quantidade de contadores reais, de 0 a 29, nos índices de 3 a $2+$`hpm_counters` |
| `hpm_width` | `core` | 64 | Largura em bits de cada contador real, de 0 a 64 |

A elaboração falha se `has_zihpm` for ligado sem `has_zicsr`. O Zihpm independe do Zicntr e funciona sem ele. Os dois parâmetros de quantidade e de largura pertencem ao manifesto do perfil, e o valor de `hpm_counters` e de `hpm_width` de cada perfil sai de lá.

Com `hpm_width` igual a 0 nenhum índice tem contador real, como se `hpm_counters` fosse 0.

## 2. Organização

Com `has_zihpm`, o Core define os 29 índices de 3 a 31 em cinco faixas de 32 endereços. O índice $K$ é o endereço de base da faixa mais $K$.

| CSR | Faixa | Escrita |
| :--- | :--- | :--- |
| `mhpmeventK` | $0x320 + K$ | Sim, guarda um código de 4 bits (os bits superiores leem zero) |
| `mhpmcounterK` | $0xB00 + K$ | Sim |
| `mhpmcounterKh` | $0xB80 + K$ | Sim |
| `hpmcounterK` | $0xC00 + K$ | Não |
| `hpmcounterKh` | $0xC80 + K$ | Não |

O banco decodifica a faixa pelos 7 bits altos do endereço e o índice pelos 5 bits baixos, de modo que a decodificação não compara o endereço inteiro. Escrever em `hpmcounterK` ou `hpmcounterKh` é acesso ilegal em qualquer índice, por serem CSRs somente leitura. Os endereços que o manual privilegiado não define dentro das faixas (`0x321`, `0x322`, `0xB01` e `0xB81`) são ilegais.

### 2.1. Índices reais e índices fixos em zero

| Índice $K$ | Leitura de qualquer CSR do índice | Escrita |
| :--- | :--- | :--- |
| $3 \le K < 3 + $`hpm_counters` | Valor do registrador | Efetiva, exceto nos espelhos |
| $K \ge 3 + $`hpm_counters` | Zero | Ignorada, sem exceção |

O manual permite fixar qualquer contador em zero, mas o endereço existe, e por isso o acesso a um índice sem contador não gera exceção. Um programa descobre quantos contadores o perfil tem escrevendo um padrão em `mhpmcounterK` e lendo de volta.

### 2.2. Largura do contador

Um contador de $W$ bits (`hpm_width`) guarda os $\min(W,32)$ bits baixos na metade baixa e os $W-32$ bits restantes na metade alta, quando $W>32$. Os bits de cada metade acima da largura leem zero, e uma escrita guarda só os bits que cabem. O contador volta a zero depois de $2^W-1$.

## 3. Estrutura

O banco `hpm_counter_bank` tem, para cada contador real, um seletor de evento, um bit de inibição e um contador próprio. Os contadores não compartilham somador, e cada um é uma instância do bloco descrito em [Zicntr](../Zicntr/description.md), com a largura da metade alta definida por `hpm_width`. A leitura escolhe o registrador pelo índice com uma árvore de multiplexadores de 32 entradas por faixa, e o índice sem contador devolve zero.

## 4. Regra de contagem

Um contador soma 1 em cada ciclo em que o bit do vetor de eventos escolhido pelo código vale `'1'`, o código não é zero e o bit de inibição do contador vale `'0'`. Um código fora da tabela de eventos não conta, mesmo que o bit do vetor valha `'1'`. Uma escrita explícita em uma metade vence o incremento do mesmo ciclo.

## 5. Tabela de eventos

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

## 6. `mcountinhibit`

O registrador `mcountinhibit` fica em `0x320`, e os bits de `mcycle` e `minstret` estão em [Zicntr](../Zicntr/description.md). O registrador existe com `has_zicntr` ou `has_zihpm`.

| Bit | Inibe | Existe quando |
| :--- | :--- | :--- |
| $3+k$ | O contador de eventos de índice $3+k$ | $k <$ `hpm_counters` |
| Demais de 3 a 31 | Nada | Nunca, leem zero e ignoram escrita |

Um contador inibido mantém o valor e continua legível e gravável.

## 7. Verificação

| Camada | O que garante |
| :--- | :--- |
| Teste de entidade do banco | Cada índice real conta o evento escolhido, o índice sem contador lê zero e ignora a escrita, a inibição age por bit, a escrita explícita vence o incremento, a metade alta avança no vai-um, a largura trunca os bits altos e o código fora da tabela conta zero, com 0, 1, 4 e 29 contadores e larguras de 1, 20, 32, 33, 40 e 64 bits |
| Prova formal de `csr_file` com Zihpm | `formal/csr_hpm_props.sv`: os 29 índices das cinco faixas, a ilegalidade dos espelhos e dos endereços não definidos, a leitura zero além de `hpm_counters`, o modelo de cada contador e a decodificação sem sobreposição, com 29, 4, 2, 5 e 3 contadores e larguras de 64, 40, 20 e 0 bits, mais um mutante por propriedade |
| Prova formal de `counter64` | Valor ideal da largura escolhida, de 1 a 64 bits, com escrita truncada |

O procedimento das provas está em [FORMAL.md](../../FORMAL.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
