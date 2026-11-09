# Conformidade do Sscofpmf

Este documento confronta cada exigência da extensão Sscofpmf (capítulo 14 e seções 3.1.9 e 3.1.10 do volume privilegiado) com o comportamento do Core, em [description.md](description.md), e aponta a evidência de cada linha.

## 1. Legenda

| Situação | Significado |
| :--- | :--- |
| Conforme | O Core cumpre a exigência e a evidência a demonstra |
| Escolha do EEI | O manual deixa a escolha à implementação, e a escolha do Core está registrada |
| Não aplicável | A exigência pertence a um modo que o Core não tem (S, U, VS ou VU) |

## 2. Matriz

| ID | Exigência | Situação | Como o Core cumpre | Evidência |
| :--- | :--- | :--- | :--- | :--- |
| O1 | `mhpmeventnh` existe para os 29 contadores, com `OF` no bit 31 | Conforme | `0x720 + K` com `K` de 3 a 31, com `HAS_SSCOFPMF` | Teste `CsrFileSscofpmf`, prova `csrof_safety` |
| O2 | `OF` é pego quando o contador estoura e só a escrita do programa o limpa | Conforme | O pulso `o_wrap` põe `OF`, e o estouro vence uma escrita simultânea | Prova `csrof_safety`, mutantes `ofp_of_not_sticky` e `ofp_overflow_loses_to_write` |
| O3 | O estouro é o estouro sem sinal dos bits implementados, e a escrita não estoura | Conforme | `o_wrap` marca a soma de todos os bits em `1` para zero, para toda largura | Prova `counter64_props`, testes `CsrFileSscofpmf` e `CsrFileSscofpmfWide`, programa `irq-lcofi` |
| O4 | Com `OF` em `1` o estouro não pede interrupção, e `OF` desabilita a interrupção | Conforme | O pedido é `o_wrap` e não `OF` | Mutante `ofp_request_ignores_of`, programa `irq-lcofi` |
| O5 | O pedido é a interrupção local 13, com `LCOFIP` em `mip` e `LCOFIE` em `mie` | Conforme | Bit 13 de `mip` (leitura e escrita) e de `mie` | Provas `csrof_safety` e mutantes `ofp_lcofip_write_lost` e `ofp_lcofie_ignored` |
| O6 | `LCOFIP` é limpo pelo programa antes de atender a interrupção | Conforme | Escrita em `mip` com o bit 13 em `0` | Programa `irq-lcofi` |
| O7 | A prioridade é a menor das interrupções de máquina | Conforme | Depois de externa, software e timer | Prova `csrof_safety`, mutante `ofp_lcofi_before_timer`, programa `irq-lcofi-priority` |
| O8 | O pedido chega ao `mip` em tempo limitado, "eventualmente, não necessariamente imediato" | Escolha do EEI | `OF` e `LCOFIP` aparecem dois ciclos depois da soma que estoura | Prova `csrof_safety` |
| O9 | `MINH` inibe a contagem no modo cujo bit está em `1` | Conforme | `MINH` (bit 30) inibe a contagem no modo máquina | Teste `CsrFileSscofpmf`, mutante `ofp_minh_ignored`, programa `irq-lcofi` |
| O10 | `SINH`, `UINH`, `VSINH` e `VUINH` são somente leitura zero sem o modo correspondente | Conforme | Os bits 29 a 26 leem zero | Teste `CsrFileSscofpmf` |
| O11 | `scountovf` reflete os `OF` para o modo S | Não aplicável | O Core não tem o modo S, e `0xDA0` é um endereço inexistente | Teste `CoreTrapPriority` |
| O12 | A delegação por `mideleg` do bit 13 | Não aplicável | O Core não tem o modo S nem `mideleg` | Teste `CoreTrapPriority` |
| O13 | Sem a extensão, `LCOFIP` e `LCOFIE` são somente leitura zero e `mhpmeventnh` não existe | Conforme | Constantes zero e endereços inexistentes sem `HAS_SSCOFPMF` | Teste `CsrFileSscofpmfOff`, provas `csri_safety` e `csrh_safety` |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
