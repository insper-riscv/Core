# Passo F.P11: classificação do barramento registrada e endereço efetivo direto do somador

🌐 [Português](P11_CLASSIFICACAO_DO_BARRAMENTO_REGISTRADA_E_ENDERECO_DO_SOMADOR.md) · [English](../../en/timing/P11_CLASSIFICACAO_DO_BARRAMENTO_REGISTRADA_E_ENDERECO_DO_SOMADOR.md)

## 1. Resumo

| Caminho | Mudança | Efeito em ciclos por instrução |
| :--- | :--- | :--- |
| Do endereço de MEM, pela comparação com as janelas da FLASH e da RAM do interconector, até o `ready` do núcleo e dali até `pipe_run` | A classificação do acesso como memória do barramento sai de EX registrada no `EX/MEM` (`o_is_bus_mem`) e o núcleo a entrega pela porta `o_ext_is_mem`; o interconector a usa no lugar da comparação do endereço | Nenhum |
| Do resultado final da ULA, pelos deslocadores e pelo E-OU da seleção, até os bits de região registrados no `EX/MEM` | O endereço efetivo de um load ou store sai direto do somador da ULA (`o_sum`), que é a operação de todo acesso à memória, e dele partem a classificação de região, o cruzamento de palavra e o deslocamento de byte do `store_manager` | Nenhum |

## 2. Classificação do barramento registrada

O núcleo conhece só a BOOT_MEMORY, a FLASH e a RAM, e já registrava em EX a região do acesso. Com $F$ e $R$ as janelas da FLASH e da RAM, e $f_b$ e $r_b$ os generics `FLASH_ON_BUS` e `RAM_ON_BUS`, o bit novo vale

$$ b = f_b\,[\,a \in F\,] + r_b\,[\,a \in R\,] $$

sobre o endereço efetivo $a$, e é o que o interconector decidia comparando o endereço de MEM com as mesmas janelas. O interconector deixa de decodificar o endereço para escolher entre o `ready` da memória do barramento e o do próprio decodificador, e o `ready` que chega ao estágio MEM, e dali a `pipe_run` e aos eventos do Zihpm, sai de um bit registrado.

Fora do acesso o bit é indiferente, como era a comparação. Um acesso desalinhado que cruza a palavra usa o mesmo bit na segunda palavra, porque só cruza dentro da região (`o_same_region`).

## 3. Endereço efetivo do somador

A ULA entrega o resultado final depois do deslocamento e da seleção E-OU das operações. O endereço efetivo $a = r_{s1} + imm$ é a saída do somador, e ele agora segue para os registradores de região, para o cálculo do cruzamento de palavra e para o `store_manager` sem passar pelos deslocadores nem pela seleção.

## 4. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| O bit registrado é a classificação do endereço, em todos os endereços de borda de região, com a FLASH no barramento e fora dele | Testes de entidade `RegExMemAddrOk` e `RegExMemAddrOkFlashBus`, contra um modelo das janelas |
| A soma direta é a soma de A e B | Teste de entidade `ALU`, que confere `o_sum` em toda soma |
| O interconector com a porta recebe o mesmo bit que a comparação daria | Asserção de simulação do interconector a cada acesso, nos testes de plataforma do Insper-RISC-V |
| O núcleo mantém o comportamento e os ciclos | Testes de entidade e de núcleo, provas formais e perfis do Core, sem alteração de resultado |

## 5. Medição

Compilação da `de0-cv` no Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT`, relógios de busca e núcleo a 100 MHz com a fase do núcleo em 3125 ps, pior caso do modelo lento a 85 °C, com o PR #104 como partida.

Folga do núcleo (ns) no modelo lento, a 85 °C e a 0 °C, e Fmax a 85 °C, com A o PR #104, A+D o #104 com este passo, A+B o #104 com o #103 e A+B+D os três juntos.

| Semente | A | A+D | A+B | A+B+D |
| ---: | :--- | :--- | :--- | :--- |
| 1 | -0,630 e -0,306 (94,07 MHz) | +0,089 e +0,263 (100,90 MHz) | -0,127 e -0,006 (98,75 MHz) | -0,386 e -0,267 (96,28 MHz) |
| 2 | -0,753 e -0,645 (93,00 MHz) | +0,290 e +0,437 (102,99 MHz) | -0,055 e -0,021 (99,45 MHz) | -0,184 e -0,011 (98,19 MHz) |
| 3 | +0,052 e +0,144 (100,52 MHz) | -0,441 e -0,369 (95,78 MHz) | -0,377 e -0,210 (96,37 MHz) | -0,356 e -0,107 (96,56 MHz) |
| 4 | -0,512 e -0,392 (95,13 MHz) | +0,116 e +0,293 (101,17 MHz) | -0,488 e -0,398 (95,35 MHz) | +0,265 e +0,401 (102,72 MHz) |
| 5 | -0,107 e -0,011 (98,94 MHz) | -0,062 e +0,009 (99,38 MHz) | -0,399 e -0,533 (96,16 MHz) | -0,586 e -0,251 (94,46 MHz) |
| Média a 85 °C | -0,390 | -0,002 | -0,289 | -0,249 |

O ganho sobre o #104 é de 0,39 ns em média e fecha o setup a 85 °C em três das cinco sementes (1, 2 e 4), e a semente 5 fica em -0,062 ns. Sobre o #104 com o #103 a média muda pouco, porque o caminho crítico passa a ser a resolução do desvio em EX (seleção do adiantamento, comparação e redirecionamento do PC) e a escrita dos contadores, e a dispersão entre sementes (0,2 a 0,4 ns) fica do tamanho do ganho. Nas sementes 3 e 5 o pior caminho de A+D sai do MEM/WB para o dado de write-back da instrução anterior. O controlador da SDRAM fica acima de +1,9 ns, o `DRAM_CLK` acima de +0,6 ns e o hold mínimo acima de +0,06 ns em todas as sementes de A+D.
---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
