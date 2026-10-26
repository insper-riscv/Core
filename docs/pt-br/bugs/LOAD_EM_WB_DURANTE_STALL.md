# Load em WB Sobrescrito por Outro Load Enquanto o Pipeline Está Parado

## 1. Resumo

Enquanto a unidade de multiplicação e divisão (M) calcula, o pipeline inteiro para e o registrador MEM/WB segura a sua instrução. Um load segurado em WB escrevia o registrador destino em todo ciclo parado. Depois do primeiro ciclo, a memória de dados passava a responder ao endereço do load parado em MEM, e o registrador recebia a palavra do load errado.

| | |
| :--- | :--- |
| Sintoma | O destino de um load guarda a palavra do load seguinte depois de um `mul`, `div` ou `rem` |
| Condição | Dois loads seguidos da RAM interna ou da porta 2 da flash, seguidos de uma instrução M que não depende do segundo load |
| Correção | WB repete o dado do seu primeiro ciclo enquanto é segurado |
| Teste | `CoreLoadStall`, um teste de núcleo com `has_m = true` e modelos síncronos de RAM e flash |

## 2. Como o Dado de um Load Chega a WB

A RAM interna e a porta 2 da flash respondem um ciclo depois do endereço, e a habilitação de leitura de MEM continua em nível alto enquanto o acesso está em MEM. No ciclo em que um load está em WB, a saída da memória é a palavra do endereço dele, apresentado no ciclo anterior.

| Estágio | Instrução | O que a memória apresenta |
| :--- | :--- | :--- |
| MEM | segundo load | o endereço dele, habilitação de leitura alta |
| WB | primeiro load | a palavra do primeiro endereço, válida neste ciclo só se o pipeline avançou |

## 3. O Que Dava Errado

A instrução M em EX para o pipeline no primeiro ciclo, com o primeiro load em WB e o segundo em MEM. Os ciclos são:

| Ciclo | WB | Palavra no barramento de dados | Registrador do primeiro load |
| :--- | :--- | :--- | :--- |
| $t_0$ | primeiro load | palavra do primeiro load | valor correto escrito |
| $t_0 + 1$ até o fim do stall | primeiro load (segurado) | palavra do segundo load | sobrescrito a cada ciclo |

O banco de registradores é escrito sempre que a instrução em WB tem `we_reg`, e o MEM/WB não muda enquanto o stall dura. O caminho de forwarding de WB recebia a mesma palavra errada.

Uma bolha em MEM esconde o problema: a habilitação de leitura fica baixa, a memória mantém a saída, e a escrita repetida leva a mesma palavra. É o caso em que a instrução M usa o segundo load, porque a bolha do load-use vai para MEM.

## 4. A Correção

Um flip-flop registra que o ciclo anterior foi um stall de EX e MEM, e um registrador guarda o dado que WB entregou no ciclo anterior. Enquanto o flip-flop está em 1, WB entrega o dado guardado:

$$
\text{wb\_data}(t) =
\begin{cases}
\text{wb\_data}(t-1) & \text{se } \text{base\_run}(t-1) = 0 \\
\text{dado bruto de WB} & \text{caso contrário}
\end{cases}
$$

O primeiro ciclo de uma instrução em WB sempre usa o dado bruto, que é o válido. Todo ciclo seguinte em que ela é segurada, e o ciclo em que o stall termina, repetem esse dado. O banco de registradores e o forwarding leem o mesmo sinal.

## 5. Custo

| Item | Valor |
| :--- | :--- |
| Hardware | 33 flip-flops e um multiplexador 2 para 1 de 32 bits |
| Timing | um nível a mais de multiplexador no caminho da memória de dados para o forwarding e o banco de registradores |
