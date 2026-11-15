# Passo F.P9: caminhos do segundo patamar do perfil completo

🌐 [Português](P9_SEGUNDO_PATAMAR_DO_PERFIL_COMPLETO.md) · [English](../../en/timing/P9_SEGUNDO_PATAMAR_DO_PERFIL_COMPLETO.md)

## 1. Resumo

| Caminho | Mudança | Efeito em ciclos por instrução |
| :--- | :--- | :--- |
| Endereço da memória de dados em MEM, que esperava a unidade de acesso desalinhado | O cruzamento da palavra é decidido em EX e registrado no `EX/MEM` (`o_cross` do `reg_ex_mem`); a `misaligned_unit` só combina o bit com a validade | Nenhum |
| Escrita de `mepc`, `mcause` e `mtval` a partir da ULA e de MEM | O `csr_file` guarda PC, causa e valor de falha do trap em registradores e grava os três CSRs um ciclo depois; `MIE` e `MPIE` mudam na própria borda do trap | Nenhum |
| Leitura dos contadores do Zihpm | O banco registra a palavra de cada faixa escolhida pelo índice, e a junção pelas seleções da instrução fica para o ciclo seguinte, o da espera já existente de `o_csr_wait` | Nenhum |

## 2. Escrita dos CSRs de trap

O trap tomado no ciclo $t$ descarta o conteúdo de `ID/EX`, de modo que a instrução em EX no ciclo $t+1$ é uma bolha. Nesse ciclo os registradores de trap gravam `mepc`, `mcause` e `mtval`, e o resultado vale a partir do ciclo $t+2$. Nenhuma leitura nem escrita de CSR, outro trap ou `MRET` cai entre os dois ciclos, e o redirecionamento do PC usa `mtvec`, que não depende da gravação.

| Instrução | Ciclo mais cedo em que lê `mepc`, `mcause` ou `mtval` |
| :--- | :--- |
| Primeira do tratador | $t+3$ |
| `MRET` do tratador | $t+3$ ou depois |

## 3. Verificação

| Garantia | Verificação |
| :--- | :--- |
| `mepc`, `mcause` e `mtval` valem dois ciclos depois do trap | Prova formal `csr_file_props` (propriedade 4) e `stage_ex_irq_props`, com a hipótese de bolha no ciclo seguinte ao trap |
| O cruzamento registrado é o que a unidade calculava em MEM | Testes de núcleo de acesso desalinhado (`cores/misaligned*`) e teste de entidade `RegExMem` |
| A leitura do banco do Zihpm devolve o valor do ciclo do endereço | Testes de entidade `HpmCounterBankRegistered` e testes de núcleo do Zihpm |
| O comportamento do núcleo é o mesmo | Todos os testes de núcleo (`cores/`) com o mesmo número de ciclos e o mesmo conteúdo final da RAM de antes da mudança |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
