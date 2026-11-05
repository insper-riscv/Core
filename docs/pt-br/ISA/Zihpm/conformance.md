# Conformidade do Zihpm

Este documento confronta cada exigência do Zihpm, em [instructions.md](instructions.md), com o comportamento do Core, em [description.md](description.md), e aponta a evidência de cada linha.

## 1. Legenda

| Situação | Significado |
| :--- | :--- |
| Conforme | O Core cumpre a exigência e a evidência a demonstra |
| Escolha do EEI | O manual deixa a escolha à implementação, e a escolha do Core está registrada |

## 2. Matriz

| ID | Exigência | Situação | Como o Core cumpre | Evidência |
| :--- | :--- | :--- | :--- | :--- |
| K5 | `hpmcounter3` a `hpmcounter31` e suas metades altas existem como CSRs somente leitura | Conforme | Com `has_zihpm` os 29 índices existem nas faixas `0xC00` e `0xC80`, com `hpm_counters` contadores reais | Teste `CsrFileZihpmFull`, prova `csrh29_safety`, programa `hpm-sweep` |
| K6 | Contador não implementado pode gerar instrução ilegal ou ler constante | Escolha do EEI | O índice sem contador lê zero e ignora a escrita, sem exceção | Teste `CsrFileZihpmReduced`, prova `csrh_safety`, programa `hpm-sweep`, modelo Sail e ACT4 com o contador fora da máscara |
| K7 | O que cada contador conta é definido pela plataforma e escolhido por um registrador | Conforme | `mhpmeventK` guarda um código de 4 bits, o código 0 não conta e a tabela de eventos está documentada | Teste `HpmCounterBankAll64`, programas `hpm-inhibit-select` e `hpm-fused-high` |
| K8 | O Zihpm depende do Zicsr | Conforme | A matriz de perfis implica `has_zicsr` e a elaboração do `core` falha sem ele | `make profiles` e a asserção do `core` |
| K9 | `mcountinhibit` inibe `cycle`, `instret` e os contadores de eventos | Conforme | Os bits 0 e 2 inibem `mcycle` e `minstret`, os bits de 3 a $2+$`hpm_counters` inibem os contadores de eventos e os demais leem zero | Testes `CsrFileZihpmFull` e `CsrFileZihpm`, prova `csrh2_safety`, programa `hpm-sweep` |

## 3. Exigências do volume privilegiado

| Exigência | Situação | Como o Core cumpre | Evidência |
| :--- | :--- | :--- | :--- |
| `mhpmcounter3` a `mhpmcounter31` (`0xB03` a `0xB1F`) são 29 contadores de 64 bits WARL, e o endereço existe ainda que o contador seja fixo em zero | Conforme | 29 endereços sempre presentes com `has_zihpm`; os `hpm_counters` primeiros contam e os demais leem zero | Prova `csrh29_safety`, teste `CsrFileZihpmFull` |
| `mhpmcounter3h` a `mhpmcounter31h` (`0xB83` a `0xB9F`) são as metades altas no RV32 | Conforme | Os mesmos 29 índices e os mesmos contadores reais | Prova `csrh29_safety` |
| `mhpmevent3` a `mhpmevent31` (`0x323` a `0x33F`) são seletores WARL, e o evento 0 significa nenhum | Conforme | Código de 4 bits, os bits superiores leem zero e o índice sem contador lê zero | Teste `HpmCounterBankAll64`, prova `csrh_safety` |
| `hpmcounterN` e `hpmcounterNh` espelham os contadores de máquina em leitura | Conforme | A faixa de espelho usa a mesma seleção de leitura, e a escrita é ilegal em qualquer índice | Teste `CsrFileZihpmFull`, mutante `hpm_mirror_writable` |
| Os bits 3 a 31 de `mcountinhibit` inibem cada contador, o bit 1 vale zero | Conforme | Um bit por contador real, os demais bits leem zero | Prova `csrh2_safety`, mutante `hpm_inhibit_reserved_bits` |
| Uma escrita explícita em um contador no mesmo ciclo do evento prevalece | Conforme | A escrita em cada metade vence o incremento do ciclo, em todos os contadores reais | Provas de `counter64` e `csrh29_safety`, teste de entidade do banco |
| A leitura de 64 bits alta, baixa, alta recupera um valor válido | Conforme | O vai-um é registrado, e a metade alta lida já soma o vai-um pendente | Provas de `counter64` com larguras de 1 a 64 bits, programa `hpm-sweep` |
| O contador tem 64 bits | Escolha do EEI | `hpm_width` de 0 a 64 bits por perfil; os bits acima da largura leem zero | Provas de `counter64` e `csrh2_safety`, testes `Counter64Width20` a `Counter64Width63` |
| Um código de evento sem significado conta zero | Conforme | Os códigos fora da tabela de eventos nunca contam | Mutante `hpm_event_table_ignored`, teste de entidade do banco |
| Os endereços que o capítulo não define dentro das faixas são ilegais | Conforme | `0x321`, `0x322`, `0xB01` e `0xB81` geram instrução ilegal | Prova `csrh29_safety`, mutante `hpm_range_overlap` |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
