# Passo F.P5: laço da busca e cache de instruções

🌐 [Português](P5_BUSCA_E_CACHE_DE_INSTRUCOES.md) · [English](../../en/timing/P5_BUSCA_E_CACHE_DE_INSTRUCOES.md)

## 1. Resumo

| | |
| :--- | :--- |
| Problema | O laço PC, cache de instruções, PC somava perto de 12 ns de dados: o PC chegava ao bit de validade da cache por um multiplexador de uma entrada por linha, à seleção da cache por comparações de endereço, e a tag lida chegava à habilitação do PC por seis níveis de lógica |
| Mudança 1 | O bit de validade vai para uma RAM lida com o endereço das RAMs de tag e de dados; a invalidação passa a ser uma varredura de uma linha por ciclo, com as consultas bloqueadas (`icache`, Memory) |
| Mudança 2 | A seleção da cache sai do endereço registrado na própria cache (generic `sel_from_kib`), e não da decodificação do PC no núcleo |
| Mudança 3 | O acerto é a conjunção de uma parte calculada cedo (seleção, sem varredura, endereço inalterado) com as duas leituras tardias (validade e tag), e a habilitação do PC fica a uma porta de `i_ic_ready` (`stage_if`) |
| Efeito em ciclos por instrução | Nenhum nos programas sem `fence.i`; cada `fence.i` e cada invalidação por região custam a varredura (256 ciclos de busca na cache de 4 KB) |

O mecanismo de contadores citado no plano para este passo (`mcycle` na habilitação do PC) não existe no núcleo atual: a habilitação do PC depende da cache, da HDU e das decisões de EX, e os contadores do Zicntr ficam no próprio domínio de EX.

## 2. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| Nada que a cache guarda é mais velho que a última invalidação, e uma região não deixa dado velho nas linhas dela | Prova formal da `icache` (Memory), com mutantes que removem o bloqueio, a varredura e a conferência de endereço |
| Os eventos 5 a 7 do Zihpm contam os mesmos acessos | Testes de entidade do Core e testes de plataforma do Insper-RISC-V |
| A habilitação do PC é a mesma função | Equivalência por construção: $hdu \wedge \neg(sdram \wedge \neg ready) = hdu \wedge \neg sdram \vee hdu \wedge sdram \wedge ready$; testes de entidade e de plataforma |

## 3. Medição

Os valores estão em [docs/pt-br/platform/timing/FRENTE-F-ONDA2.md do Insper-RISC-V](../../../../docs/pt-br/platform/timing/FRENTE-F-ONDA2.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
