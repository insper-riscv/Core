# Passo F.P7: limpeza dos registradores de barreira só nos bits de controle

🌐 [Português](P7_FLUSH_SO_NOS_BITS_DE_CONTROLE.md) · [English](../../en/timing/P7_FLUSH_SO_NOS_BITS_DE_CONTROLE.md)

## 1. Resumo

| | |
| :--- | :--- |
| Problema | O descarte por desvio, salto ou trap nasce no fim do laço de EX (comparador da ULA, `o_branch_taken`) e limpava de forma síncrona cerca de 200 bits de `ID/EX`, mais os campos de `IF/ID` e `EX/MEM`. A rede de limpeza, com fan-out alto, somava de 4 a 4,5 ns ao laço de EX |
| Mudança | Os quatro registradores (`reg_if_id`, `reg_id_ex`, `reg_ex_mem` e `reg_mem_wb`) limpam com `i_flush` ou `i_rst` apenas os bits de controle. Os campos de dados só têm habilitação (`i_en`) |
| Efeito no comportamento | Nenhum. Uma bolha sai dos registradores com `o_valid` e os habilitadores de efeito colateral em zero, e todo uso do campo de dados depende deles |
| Efeito em ciclos por instrução | Nenhum |

## 2. Campos de cada registrador

| Registrador | Limpos por `i_flush` e `i_rst` | Só com habilitação |
| :--- | :--- | :--- |
| `reg_if_id` | validade, campo `opcode` da instrução | `pc`, `pc4`, bits `[31:7]` da instrução |
| `reg_id_ex` | validade, índices `rs1` e `rd`, seletores, código e seleção da ULA, `we_reg`, `we_ram`, `re_ram`, `en_ram`, `is_csr`, `is_muldiv`, `illegal`, `opcode`, `funct3` | `pc`, `pc4`, `rs1_val`, `rs2_val`, `imm`, seletores de adiantamento |
| `reg_ex_mem` | validade, `rd`, `we_reg`, `we_ok`, habilitadores de memória, modo de extensão, seletor de write-back, classificação do endereço | `pc`, `funct3`, `alu_out`, `store_data`, `byte_mask` |
| `reg_mem_wb` | validade, `rd`, `we_reg`, `we_ok`, modo de extensão, seletor de write-back, classificação do endereço | `alu_out` |

## 3. Por que o valor de uma bolha nunca produz efeito

| Uso do campo de dados | Condição que o trava |
| :--- | :--- |
| Desvio, salto e exceção em EX | `i_valid`, que vem de `o_valid` do `ID/EX` |
| Escrita no banco de registradores e adiantamento | `we_reg` e `we_ok`, zerados pela limpeza |
| Acesso à memória em MEM e escrita de `mepc` por exceção de MEM | validade e habilitadores de memória do `EX/MEM`, zerados pela limpeza |
| Decodificação em ID de uma instrução descartada | `i_ifid_valid` na detecção de hazard e na validade entregue ao `ID/EX`, e `opcode` zerado, que não decodifica efeito |

## 4. Verificação

| Garantia | Verificação |
| :--- | :--- |
| Cada registrador limpa só os controles e mantém ou captura os dados conforme `i_en` | Testes de entidade `RegIfId`, `RegIdEx`, `RegExMem` e `RegMemWb` |
| O comportamento do núcleo é o mesmo | Todos os testes de núcleo (`cores/`) com o mesmo número de ciclos e o mesmo conteúdo final da RAM de antes da mudança |
| As provas formais seguem valendo | `make formal` |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
