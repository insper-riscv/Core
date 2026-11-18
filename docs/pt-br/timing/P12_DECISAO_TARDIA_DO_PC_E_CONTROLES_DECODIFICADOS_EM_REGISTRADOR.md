# Passo F.P12: decisão tardia do PC, decodificação do MEM/WB e load registrado para a detecção de dependência

🌐 [Português](P12_DECISAO_TARDIA_DO_PC_E_CONTROLES_DECODIFICADOS_EM_REGISTRADOR.md) · [English](../../en/timing/P12_DECISAO_TARDIA_DO_PC_E_CONTROLES_DECODIFICADOS_EM_REGISTRADOR.md)

## 1. Resumo

| Caminho | Mudança | Efeito em ciclos por instrução |
| :--- | :--- | :--- |
| Da comparação do desvio em EX, pelo `pc_src`, pela habilitação do PC e pela escolha da fonte, até o registrador do PC | O desvio ou salto tomado entra só no seletor final e na habilitação do `pc_fetch` (`i_late_take` e `i_late_jalr`), e o `pc_src` e a habilitação da HDU deixam de depender dele | Nenhum |
| Dos dois bits baixos do endereço registrado em MEM/WB, pelo deslocamento do load que cruza a palavra e pelo extensor, até o dado de write-back registrado | O MEM/WB registra a posição do dado (`o_ext_off`) e o deslocamento em um bit por byte (`o_cross_sel`), e o estágio WB junta as palavras por E-OU em vez de um deslocador | Nenhum |
| Do `r_re_ram` e do `rd` de ID/EX e de EX/MEM, pelas comparações da detecção de load-use, até a habilitação do PC | ID/EX e EX/MEM registram o bit de load com `rd` diferente de `x0` (`o_ld`), e a HDU deixa de comparar `rd` com zero | Nenhum |
| Da comparação do desvio em EX, pela exceção de endereço de desvio desalinhado, até as escritas dos contadores e dos CSRs | O `trap_unit` entrega também a exceção sem a de desvio desalinhado (`o_take_nocf`), e o `csr_file` barra as escritas de CSR com ela (`i_trap_early`), porque uma instrução CSR nunca toma desvio | Nenhum |

## 2. Decisão tardia do PC

Com $t$ a decisão de desvio ou salto de EX liberada pelo pipeline e $r$ o redirecionamento prioritário, o próximo PC e a habilitação passam a ser

$$ pc' = \begin{cases} pc_{r} & r = 1 \\ pc_{alvo} & t = 1,\ r = 0 \\ pc_{cedo} & \text{caso contrário} \end{cases} \qquad e = e_{hdu} \lor r \lor t $$

em que $pc_{cedo}$ é o valor que o seletor de quatro fontes entrega sem a decisão de EX. Como $t$ chega por último, ele só alimenta a escolha final do alvo e a habilitação, e o alvo é o do `JALR` com `i_late_jalr` e o do desvio ou `JAL` sem ele. Sem o desvio na seleção, o `pc_src` fica em PC + 4 ou em redirecionamento, e a habilitação da HDU não inclui mais o termo do desvio.

## 3. Decodificação do MEM/WB

Com $o$ os dois bits baixos do endereço e $c$ o bit de cruzamento de palavra, o MEM/WB registra

$$ ext\_off = \begin{cases} 0 & c = 1 \\ o & c = 0 \end{cases} \qquad cross\_sel_k = c \cdot [\,o = k\,],\ k \in \{1,2,3\} $$

e a palavra entregue ao extensor é a leitura da memória com $c = 0$ ou a junção da leitura com a primeira palavra deslocada de $k$ bytes com $cross\_sel_k = 1$. O cruzamento só existe com $o \ne 0$, então os três bits de seleção e o bit $c$ nunca ficam todos em zero ao mesmo tempo com $c = 1$.

## 4. Load registrado e exceção sem desvio

A detecção de dependência de load usa o bit registrado $ld = re\_ram \cdot [\,rd \ne x0\,]$ de ID/EX e de EX/MEM, de modo que a comparação com zero sai do caminho que termina na habilitação do PC.

A exceção $trap = early \lor cf$ do estágio EX tem a parte $cf$ (desvio ou salto tomado com alvo desalinhado) dependente da comparação do desvio. As escritas dos contadores e dos CSRs de máquina só valem para uma instrução CSR, que nunca é desvio, então usam $early$. A entrada na exceção (`mstatus`, `mepc`, `mcause`) continua usando a exceção completa.

## 5. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| O PC carrega o alvo certo, congela sem habilitação e dá prioridade ao redirecionamento sobre a decisão tardia | Teste de entidade `PcFetch` |
| A junção, a extensão e a seleção do dado de write-back são as mesmas | Testes de entidade `StageWb` e `RegMemWb` |
| O bit de load e a detecção de dependência valem com e sem `rd` igual a `x0` | Testes de entidade `RegIdEx`, `RegExMem`, `HazardDetectionUnit` e `StageId` |
| A exceção sem desvio não inclui o desvio desalinhado e as escritas de CSR seguem barradas por exceção | Testes de entidade `TrapUnit` e `CsrFile*`, e provas formais dos contadores e do banco de CSR |
| O núcleo mantém o comportamento e os ciclos | Testes de entidade e de núcleo, provas formais e perfis do Core, sem alteração de resultado |

## 6. Medição

Compilação da `de0-cv` no Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT`, relógios de busca e núcleo a 100 MHz com a fase do núcleo em 3125 ps, pior caso do modelo lento a 85 °C. A coluna A+B+D é a soma dos PRs #104, #103 e #105, e a coluna final soma a ela este passo.

| Semente | A+D (#104 e #105) | A+B+D | A+B+D com este passo |
| ---: | :--- | :--- | :--- |
| 1 | +0,089 ns | -0,386 ns | +0,419 ns e +0,528 ns a 0 °C (104,37 MHz) |
| 2 | +0,290 ns | -0,184 ns | +0,450 ns e +0,473 ns a 0 °C (104,71 MHz) |
| 3 | -0,441 ns | -0,356 ns | +0,138 ns e +0,134 ns a 0 °C (101,40 MHz) |
| 4 | +0,116 ns | +0,265 ns | +0,501 ns e +0,467 ns a 0 °C (105,27 MHz) |
| 5 | -0,062 ns | -0,586 ns | +0,358 ns e +0,446 ns a 0 °C (103,71 MHz) |
| Média a 85 °C | -0,002 ns | -0,249 ns | +0,373 ns |

O controlador da SDRAM fica acima de +2,1 ns, o `DRAM_CLK` acima de +0,6 ns e o hold mínimo acima de +0,25 ns no modelo lento e de +0,06 ns no rápido, em todas as sementes.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
