# Passo F.P6c: leitura registrada do banco do Zihpm

🌐 [Português](P6_LEITURA_REGISTRADA_DO_ZIHPM.md) · [English](../../en/timing/P6_LEITURA_REGISTRADA_DO_ZIHPM.md)

## 1. Resumo

| | |
| :--- | :--- |
| Problema | A leitura de um contador do Zihpm passava por um multiplexador de 29 contadores (nove níveis de lógica, com 1,3 a 1,9 ns de roteamento entre eles), seguia para o resultado da instrução e, nos `csrrs`, `csrrc` e `csrrw`, voltava à escrita do contador de destino: 12,3 ns de dados num período de 10 ns |
| Mudança | O banco (`hpm_counter_bank`, generic `registered_read`) registra o valor lido; a instrução CSR que acessa o banco espera um ciclo em EX (`o_csr_wait` do `stage_ex`, somado ao stall do pipeline), lê o valor registrado no ciclo seguinte e escreve a partir dele |
| Efeito no comportamento | O valor lido é o do contador no ciclo da espera, em que todas as instruções mais velhas já foram contadas e a própria instrução ainda não; as escritas são as mesmas |
| Efeito em ciclos por instrução | Mais um ciclo por instrução CSR que acessa `mcountinhibit`, `mhpmeventK`, `mhpmcounterK` ou `mhpmcounterKh` (e os espelhos); zero nos demais programas |

## 2. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| A leitura devolve o valor correto e os contadores contam os mesmos eventos | Testes de entidade do `csr_file` e do banco (modo combinacional, inalterado) e testes de núcleo do Zihpm (`cores/zihpm`), que executam o banco registrado |
| A escrita acontece uma vez, no ciclo em que a instrução avança | `csr_commit` depende de `i_pipe_run`, que está em zero no ciclo da espera |
| O custo é de um ciclo por leitura | Teste de núcleo `test_a_bank_read_costs_one_cycle`: 16 leituras seguidas de `mhpmcounter3` levam exatamente 16 ciclos a mais que 16 leituras de `mscratch` (diferença de `mcycle`) |
| Uma leitura logo depois da escrita e o `csrrs` veem o valor certo | Teste de núcleo `test_a_read_right_after_a_write_sees_the_new_value` |
| A leitura de um CSR logo depois de um contador do banco não recebe os bits dele | Teste de núcleo `test_a_counter_read_does_not_leak_into_the_next_csr_read` |
| O banco registrado devolve o valor do ciclo do endereço | Teste de entidade `HpmCounterBankRegistered` (5 testes) |
| `mcountinhibit` e `mhpmevent` continuam valendo | Provas formais do `csr_file` (modo combinacional) e testes de núcleo |

## 3. Medição

Os valores estão em [docs/pt-br/platform/timing/FRENTE-F-ONDA2.md do Insper-RISC-V](../../../../docs/pt-br/platform/timing/FRENTE-F-ONDA2.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
