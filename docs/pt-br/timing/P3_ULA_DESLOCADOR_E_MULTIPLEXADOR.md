# Passo F.P3: deslocador e multiplexador de resultado da ULA

## 1. Resumo

| | |
| :--- | :--- |
| Problema | O deslocador à direita e o multiplexador do resultado da ULA somavam 4,5 ns e seis níveis de lógica |
| Mudança | Os deslocadores (à esquerda e à direita, esta com preenchimento de sinal selecionável) são estágios de multiplexadores 4 para 1, um por dois bits da quantidade, e o resultado sai de um E-OU com seleção one-hot decodificada em ID |
| Níveis do deslocador | Três: os estágios cobrem os bits 1:0, 3:2 e 4 da quantidade |
| Somador | Um só, compartilhado por soma, subtração, comparações, JALR, LUI e desvios |
| Efeito no comportamento | Nenhum |

## 2. Estrutura

| Bloco | Como é feito |
| :--- | :--- |
| Somador-subtrator | O bit de inversão da operação entra em B com carry-in 1; o sinal e o carry-out da diferença dão o menor-que com e sem sinal |
| Igualdade | Comparador próprio, que não espera a cadeia de carry |
| Deslocadores | $\lceil 5/2 \rceil = 3$ estágios de multiplexadores 4 para 1 (uma LUT de 6 entradas cada) |
| Grupo rápido do resultado | XOR, OR, AND e os bits de SLT e SLTU, que não esperam o somador nem os deslocadores |
| Grupo lento do resultado | Soma e deslocamentos |

## 3. Equivalência com a ULA de referência

A prova formal `alu_props.sv` compara a saída da ULA com os operadores da linguagem (soma, diferença, comparações com e sem sinal, três deslocamentos pelos cinco bits baixos de B, lógicos bit a bit, LUI, JALR e as seis condições de desvio), para todas as 18 operações e todos os pares de operandos, com a seleção one-hot que o decodificador produz para cada operação.

| Prova | Resultado esperado |
| :--- | :--- |
| Equivalência do dado e da condição de desvio | Passa |
| Cover: deslocamento aritmético, comparações que cruzam o sinal, JALR e desvios | Alcançáveis |
| Dez mutantes (preenchimento de sinal, bit do SLT, bit 0 do JALR, dígitos dos deslocadores, igualdade, LUI, carry da subtração, seleção do XOR, condição do BGEU) | Todos pegos |

O teste de entidade `ALU` continua cobrindo as 18 operações com valores aleatórios.

## 4. Medição

O RTL deste passo é o da medição de `P1_EXCECAO_DE_ACESSO_EM_MEM.md`, seção 4. Os caminhos que atravessam a ULA (de `ID/EX` e do adiantamento até `EX/MEM`) não estão entre os piores do relatório do núcleo, que são a leitura de CSR realimentando a escrita de CSR e o laço da cache de instruções.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
