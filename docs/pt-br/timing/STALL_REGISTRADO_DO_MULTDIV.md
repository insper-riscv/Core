# Stall do multiplicador e do divisor vindo de um flip-flop

## 1. Resumo

A unidade de multiplicação e divisão (RV32M) segura o pipeline inteiro enquanto calcula. O sinal que faz isso, o stall do M, sai de um flip-flop próprio, e só o primeiro ciclo da operação é combinacional. O comportamento visível do core não muda; muda o caminho que o sinal percorre até os registradores do pipeline.

| | |
| :--- | :--- |
| Problema | O pulso de término do multiplicador e do divisor entrava no stall do pipeline por uma cadeia de 7 níveis de lógica, e essa cadeia aparecia entre os caminhos que violam o tempo quando o clock do core sobe |
| Mudança | O stall do M é a soma (OU) do início combinacional de um ciclo com um flip-flop que guarda o estado de ocupado do ciclo anterior |
| Efeito no comportamento | Nenhum: o stall tem o mesmo valor em todos os ciclos |
| Efeito no tempo (100 MHz, modelo lento) | O pior caminho que sai do multiplicador passa de −2,3 ns para +2,0 ns, e o do divisor de −2,5 ns para +2,2 ns |
| Verificação | Testes de entidade do Core (17 grupos) e suíte de simulação de 98 programas, sem falhas |

## 2. Como o stall do M funciona

O M roda no estágio EX e precisa de vários ciclos: 33 para a multiplicação (Booth) e 34 para a divisão (sem restauração). Enquanto isso o estágio EX e os que vêm antes ficam parados.

| Ciclo | O que acontece na unidade | Stall |
| :--- | :--- | :--- |
| $t_0$ | Uma instrução M válida chega ao EX; o pulso de início sobe | sobe no mesmo ciclo (combinacional) |
| $t_0+1$ até $t_d-1$ | O laço soma, subtrai e desloca uma vez por ciclo | continua |
| $t_d$ | O pulso de término sobe e o resultado é capturado | continua |
| $t_d+1$ | O pipeline avança | cai |

O stall precisa subir já em $t_0$: se subisse um ciclo depois, a instrução M passaria pelo EX sem esperar. Por isso o primeiro ciclo continua combinacional.

## 3. Por que o stall estava no caminho crítico

O stall do M controla a escrita do PC e dos registradores de barreira. Num ciclo parado, o PC não avança e nenhum desvio, retorno de trap ou `mret` pode redirecionar o fluxo. O sinal que sai do pulso de término atravessava, em sequência:

| Nível | Lógica |
| :--- | :--- |
| 1 a 2 | OU dos sinais de ocupado e de término do M para formar o stall |
| 3 | Habilitação de escrita do PC |
| 4 | Decisão de tomar o `mret` (só vale com o pipeline andando) |
| 5 a 6 | Habilitação do PC e do registrador ID/EX |
| 7 | Seleção do valor de `rs1` que entra no ID/EX |

Com o período curto, essa cadeia de 7 níveis de lógica, com roteamento de até 1,7 ns entre os níveis, soma cerca de 12 ns e viola o tempo. O trecho que a mudança remove são os dois primeiros níveis: o pulso de término deixa de ser uma entrada da lógica de stall.

O laço do multiplicador e do divisor não é o limite. Em um período de 20 ns eles têm folga de 11,4 ns (multiplicador) e 14,2 ns (divisor), o que dá um limite isolado de cerca de 116 MHz e 172 MHz no modelo lento. O que limita é o controle do stall, e não a aritmética.

## 4. A mudança

O stall do M passa a valer

$$
\text{stall}(t) = \text{inicio}(t) \;\lor\; \text{ativo}(t), \qquad \text{ativo}(t) = \text{ocupado}(t-1)
$$

em que $\text{inicio}(t)$ é o pulso de início combinacional (um ciclo) e $\text{ocupado}$ é o OU dos sinais de ocupado do multiplicador e do divisor. O flip-flop guarda $\text{ocupado}$ do ciclo anterior.

A equivalência com o stall que usa o pulso de término diretamente vem da duração de $\text{ocupado}$ em cada ciclo da operação:

| Ciclo | ocupado | término | stall com o pulso de término | stall com o flip-flop |
| :--- | :--- | :--- | :--- | :--- |
| $t_0$ | 1 (início) | 0 | 1 | 1 (início) |
| $t_0+1$ a $t_d-1$ | 1 | 0 | 1 | 1 (ocupado do ciclo anterior) |
| $t_d$ | 0 | 1 | 1 | 1 (ocupado de $t_d-1$) |
| $t_d+1$ | 0 | 0 | 0 | 0 (ocupado de $t_d$ é 0) |

O sinal de ocupado do multiplicador e do divisor cai no mesmo ciclo em que o pulso de término sobe, e fica em 1 no ciclo anterior. Por isso o ocupado atrasado de um ciclo cobre exatamente o ciclo de término.

## 5. Medições

Análise de tempo do Quartus (modelo lento, 85 °C) sobre a plataforma `internal-mem` com o clock do core a 100 MHz.

| Caminho | Sem o flip-flop | Com o flip-flop |
| :--- | :--- | :--- |
| Pior saindo do multiplicador | −2,304 ns | +1,981 ns |
| Pior saindo do divisor | −2,486 ns | +2,219 ns |
| Caminhos do M entre os 800 piores | presentes | nenhum |
| Pior caminho do projeto | −7,623 ns | −7,267 ns |

O pior caminho do projeto vem da leitura da RAM de dados até os registradores `reg_ex_mem` e `reg_id_ex`, e continua violando em um período de 10 ns. Esse caminho é independente do M.

Verificação funcional:

| Verificação | Resultado |
| :--- | :--- |
| Testes de entidade do Core | 17 grupos, 0 falhas |
| Suíte de simulação (plataforma `internal-mem`) | 98 de 98 |

## 6. Custo e limites

| Item | Valor |
| :--- | :--- |
| Hardware | 1 flip-flop |
| Latência de uma operação M | 33 e 34 ciclos, a mesma |
| Sinais novos | nenhum no contrato do módulo; o stall continua sendo a saída `o_stall` |

A mudança não eleva a frequência do core por si só: ela retira o M da lista de caminhos que violam o tempo. O limite passa a ser o caminho da leitura da RAM e o cruzamento entre os três clocks defasados do pipeline.
