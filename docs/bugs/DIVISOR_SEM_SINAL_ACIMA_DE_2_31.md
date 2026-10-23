# Divisor sem sinal errado com divisor acima de 2^31

## 1. Resumo

O divisor do RV32M guardava o resto parcial em 33 bits com sinal e, a cada passo, descartava o bit mais alto antes de deslocar. Com um divisor sem sinal maior que $2^{31}$, o resto parcial chega a $\pm 2^{31}$ ou mais em módulo, o bit descartado deixa de ser só extensão de sinal, e o passo seguinte soma ou subtrai o divisor do lado errado. O quociente e o resto saem errados.

| | |
| :--- | :--- |
| Sintoma | `divu` e `remu` devolvem quociente e resto errados quando o divisor é maior que $2^{31}$ |
| Condição | Operação sem sinal com divisor $> 2^{31}$, para a maioria dos dividendos |
| Correção | Resto parcial e divisor internos com 34 bits |
| Teste | Teste de entidade do divisor contra o resultado definido pela ISA, com pares de valores de borda e pares aleatórios |
| Descoberto por | Testes `M-divu-00` e `M-remu-00` do ACT4 |

DIV e REM não são afetados: o divisor entra em valor absoluto, no máximo $2^{31}$, e o resto parcial nunca passa de $2^{31}$.

## 2. Como o divisor calcula

A divisão sem restauração repete 32 vezes, sobre o par (resto parcial $A$, quociente $Q$) e o divisor $M$ positivo:

1. Desloca o par $\{A, Q\}$ uma posição à esquerda; o bit mais alto de $Q$ vira o bit menos significativo de $A$.
2. Se $A \ge 0$, subtrai $M$; senão, soma $M$.
3. O bit menos significativo de $Q$ recebe 1 se o novo $A \ge 0$, senão 0.

Ao fim, se $A < 0$, soma $M$ uma última vez para obter o resto. O sinal de $A$ decide a operação de cada passo, então $A$ precisa representar o resto sem ambiguidade de sinal.

## 3. Faixa de valores do resto parcial

Entre os passos, o resto parcial satisfaz $-M \le A < M$. Logo, depois do deslocamento:

$$
-2M \le A_{\text{deslocado}} = 2A + b < 2M, \qquad b \in \{0, 1\}
$$

Com $M < 2^{32}$ (divisor sem sinal de 32 bits), o valor deslocado alcança quase $2^{33}$ em módulo. Representar $[-2^{33}, 2^{33})$ em complemento de dois exige 34 bits.

| Largura de $A$ | Faixa de $A_{\text{deslocado}}$ representável | Divisor máximo correto |
| :--- | :--- | :--- |
| 33 bits | $[-2^{32}, 2^{32})$ | $2^{31}$ |
| 34 bits | $[-2^{33}, 2^{33})$ | $2^{32} - 1$ |

O deslocamento anexava o bit de $Q$ aos 32 bits baixos de $A$, descartando o bit 32. Isso só equivale a estender o sinal enquanto $-2^{31} \le A < 2^{31}$, o que vale para qualquer divisor até $2^{31}$. Acima disso, $A$ sai dessa faixa já nos primeiros passos, porque um dividendo pequeno deixa o resto parcial negativo perto de $-M$. O bit descartado carregava informação, e o valor deslocado muda de sinal ou de magnitude.

## 4. Exemplo

`divu` com dividendo 1 e divisor $\texttt{0x80000001}$. O resultado correto é quociente 0 e resto 1.

| Largura de $A$ | Quociente | Resto |
| :--- | :--- | :--- |
| 33 bits | $\texttt{0x7FFFFFFE}$ | 3 |
| 34 bits | 0 | 1 |

Com esse dividendo, $A$ fica negativo logo no primeiro passo, perto de $-M \approx -2^{31}$. A partir daí, o deslocamento de 33 bits perde o bit 32 de $A$ e cada passo seguinte parte de um valor errado.

## 5. A correção

| Elemento | Largura |
| :--- | :--- |
| Resto parcial $A$ e variáveis do passo | 34 bits com sinal |
| Divisor $M$ | 34 bits com sinal, com zero extendido nos dois bits mais altos |
| Deslocamento | $A_{\text{deslocado}} = A[32{:}0] \,\&\, Q[31]$ |

As saídas continuam com 32 bits: o resto final cabe em 32 bits, pois $0 \le A < M < 2^{32}$ ao fim da etapa de correção.

## 6. Como o teste prova a correção

O teste de entidade `non_restoring_divider` roda o divisor isolado e compara quociente e resto com o resultado que a ISA define, calculado em Python.

| Teste | Entradas |
| :--- | :--- |
| Bordas sem sinal | Todos os pares de $\{0, 1, 2, 3, \texttt{0x7FFFFFFF}, \texttt{0x80000000}, \texttt{0x80000001}, \texttt{0xFFFFFFFE}, \texttt{0xFFFFFFFF}\}$ |
| Bordas com sinal | Os mesmos pares, incluindo $-2^{31} / -1$ e divisão por zero |
| Aleatório | 60 pares de 32 bits, nos dois modos, com semente fixa |

O teste de bordas sem sinal exercita 23 pares que o divisor de 33 bits calcula errado, todos com divisor $\ge \texttt{0x80000001}$; com 34 bits nenhum falha. Os três testes passam. A suíte de simulação do projeto (89 programas) e as 47 execuções do ACT4 para as extensões I e M passam com o divisor corrigido.
