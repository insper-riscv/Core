# Passo F.P4: classificação do endereço efetivo registrada em EX/MEM

🌐 [Português](P4_CLASSIFICACAO_DO_ENDERECO_REGISTRADA.md) · [English](../../en/timing/P4_REGISTERED_ADDRESS_CLASS.md)

## 1. Resumo

| | |
| :--- | :--- |
| Problema | Em MEM, a região do endereço (FLASH, SDRAM, memória principal, mesma região das duas palavras de um acesso que cruza) era decodificada de `r_alu_out` e do endereço da segunda palavra, e o resultado alimentava a exceção de acesso, o stall de acesso desalinhado, o stall da SDRAM e, por eles, a habilitação e a limpeza dos registradores do pipeline |
| Mudança | A classificação sai do resultado da ULA em EX e é registrada em EX/MEM (`o_is_flash`, `o_is_sdram`, `o_in_main`, `o_same_region`); `stage_mem`, `misaligned_unit` e a `trap_unit` de MEM partem dos bits registrados (generics `flags_registered` e `ea_flags_external`) |
| Efeito no comportamento | Nenhum: a classificação é a mesma, um estágio mais cedo |
| Efeito em ciclos por instrução | Nenhum |

## 2. Caminho antes e depois

| Etapa | Antes | Depois |
| :--- | :--- | :--- |
| Origem da classificação | Comparações de 32 bits sobre `r_alu_out` e sobre o endereço da segunda palavra (`cross` na frente) | Registradores de EX/MEM carregados da saída da ULA |
| Cadeia em MEM | Comparações, junção das causas, `cross`, decodificação da SDRAM, stall, habilitações do pipeline | Junção das causas sobre bits registrados, stall, habilitações do pipeline |
| Fonte em EX | Não existe | Saída da ULA (`o_alu_result` do `stage_ex`), e não o resultado final, para não herdar a leitura de CSR |

O endereço da segunda palavra de um acesso que cruza fica na mesma região do primeiro sempre que o acesso é executado, porque a `trap_unit` de MEM gera a exceção quando as duas palavras não estão na mesma região.

## 3. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| A classificação registrada é a do endereço de EX e é limpa no flush e no reset | Teste `RegExMem` (`test_address_class_is_registered`) |
| Cada causa e cada região da `trap_unit`, com os bits de região vindos de fora | Provas formais da `trap_unit` e testes de entidade do `stage_mem` e da `misaligned_unit` (caminho decodificado) |
| O pipeline completo continua preciso | Testes de entidade do Core (`CoreMemTrapEx`, `CoreMisalignedHalf` e a suíte), perfis do `make profiles` |

## 4. Medição

Compilação da `de0-cv` (perfil completo) no Quartus Prime 25.1 Lite, modo `HIGH PERFORMANCE EFFORT`, semente 1, modelo lento a 85 °C, relógios de busca e núcleo a 83,333 MHz com a fase do núcleo em 6000 ps. Os valores completos estão em [docs/pt-br/platform/timing/FRENTE-F-ONDA2.md do Insper-RISC-V](../../../../docs/pt-br/platform/timing/FRENTE-F-ONDA2.md).

| Par de relógios | Antes (ns) | Depois (ns) |
| :--- | ---: | ---: |
| núcleo para núcleo, pior folga | -0,639 | -0,289 |

## 5. Custo em ciclos por instrução

Nenhum, porque a classificação é a mesma e o ciclo em que o stall e a exceção ocorrem não muda.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
