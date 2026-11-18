# Passo F.P10: exceção de endereço e palavra seguinte registradas

🌐 [Português](P10_EXCECAO_DE_ENDERECO_E_PALAVRA_SEGUINTE_REGISTRADAS.md) · [English](../../en/timing/P10_EXCECAO_DE_ENDERECO_E_PALAVRA_SEGUINTE_REGISTRADAS.md)

## 1. Resumo

| Caminho | Mudança | Efeito em ciclos por instrução |
| :--- | :--- | :--- |
| Do `trap_unit` de MEM até a habilitação de escrita da cache de dados | A decisão de desalinhamento e de store em região só de leitura sai de três bits registrados no `EX/MEM` (`o_ea_xlast`, `o_ea_unal` e `o_ea_stf`) combinados com a região também registrada; o `stage_mem` e o `core` decidem a exceção de endereço e a validade do acesso nesse único nível de lógica (generic `ea_ok_registered`) | Nenhum |
| Do endereço registrado até o endereço da memória, pelo somador e pelo seletor da `misaligned_unit` | A palavra seguinte à do acesso é registrada no ciclo da etapa 1 e a etapa 2 a seleciona, sem o somador no caminho do endereço; o endereço da memória sai da unidade sem o seletor por `mis_cross`, porque fora da etapa 2 a unidade apresenta o próprio endereço do `EX/MEM` | Nenhum |

## 2. Exceção de endereço

O `trap_unit` de MEM continua gerando a causa e o `mtval`. A decisão de que o acesso gera exceção, que fechava o caminho até a escrita da memória, parte agora de bits decididos em EX a partir do `funct3`, dos controles de leitura e escrita e dos dois bits baixos do endereço efetivo, que o somador da ULA entrega cedo. Os bits da região (`o_in_main`, `o_same_region`, `o_ok_wr`) já eram registrados.

Com $m$ a memória principal, $l$ a última palavra da região, $x$ o acesso que cruza a palavra, $u$ o acesso desalinhado, $s$ o store e $w$ a região que não aceita escrita, a exceção de endereço vale

$$ e = m\,l\,x + \bar{m}\,u + \bar{w}\,s_f $$

com Zicclsm, onde $s_f$ é o store com `HAS_ACCESS_FAULTS`. Sem Zicclsm, $x$ é substituído por $u$ e o termo da última palavra deixa de existir. Os três bits registrados são $x$, $u$ e $s_f$, e todos valem zero sem `HAS_ZICSR`.

| Região do endereço | Acesso que é exceção |
| :--- | :--- |
| Memória principal, fora da última palavra de uma região | Só o store em região que não aceita escrita (a FLASH no barramento) |
| Última palavra de uma região da memória principal | Também o acesso que cruza a palavra |
| Fora da memória principal (BOOT_MEMORY e FLASH direta) | Todo acesso desalinhado e todo store |

## 3. Palavra seguinte e endereço da memória

O endereço do acesso fica estável nas etapas 1 e 2 da `misaligned_unit`. A palavra seguinte capturada no fim da etapa 1 vale durante toda a etapa 2, de modo que o endereço apresentado à memória sai de um multiplexador de registradores, e não do somador de 30 bits.

Fora da etapa 2 a unidade apresenta o endereço do `EX/MEM`, de modo que o endereço da memória é a saída dela sem o seletor que dependia da exceção de endereço.

## 4. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| A exceção composta dos bits registrados é a do `trap_unit`, em todos os `funct3`, controles, bytes de endereço e regiões, com a FLASH pela porta direta e no barramento | Testes de entidade `RegExMemAddrOk` e `RegExMemAddrOkFlashBus`, contra um modelo das regras de exceção |
| O núcleo continua preciso, com a causa e o `mtval` do `trap_unit` | Provas formais do `trap_unit` e do `stage_mem`, testes de núcleo de acesso desalinhado e de exceção em MEM |
| A palavra seguinte da etapa 2 é a mesma de antes | Testes de núcleo de acesso desalinhado (`cores/misaligned*`) com o mesmo número de ciclos |

## 5. Medição

Compilação da `de0-cv` com o Core `f61b96d` como partida, o Insper-RISC-V, o Tools e o Peripherals da `main` no Quartus Prime 25.1 Lite, `HIGH PERFORMANCE EFFORT`, semente 5, relógios de busca e núcleo a 100 MHz com a fase do núcleo em 3125 ps, pior caso do modelo lento a 85 °C.

| Passo | Folga do núcleo (ns) | Fmax do núcleo (MHz) |
| :--- | ---: | ---: |
| Partida (Core `f61b96d`) | -1,236 | 89,0 |
| Exceção de endereço registrada | -0,316 | 96,94 |
| Com os três bits registrados e a palavra seguinte registrada | -0,316 | 96,94 |
| Com o endereço da memória sem o seletor por `mis_cross` | -0,107 | 98,94 |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
