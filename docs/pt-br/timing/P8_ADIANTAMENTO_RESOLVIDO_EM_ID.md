# Passo F.P8: seleção do adiantamento resolvida em ID e replicada

🌐 [Português](P8_ADIANTAMENTO_RESOLVIDO_EM_ID.md) · [English](../../en/timing/P8_ADIANTAMENTO_RESOLVIDO_EM_ID.md)

## 1. Resumo

| | |
| :--- | :--- |
| Problema | O estágio EX escolhia a fonte de cada operando com seis bits registrados (três casamentos e três validades), e o resultado, com fan-out de 132, comandava o multiplexador de operando. A seleção e a rede somavam cerca de 2,9 ns ao início do laço de EX |
| Mudança | O estágio ID calcula o seletor já resolvido (`forwarding_match` com as validades, depois `forwarding_unit` com a prioridade), e o `ID/EX` o registra em `FWD_COPIES` cópias por operando. Cada cópia comanda uma fatia do multiplexador de operando em EX |
| Efeito no comportamento | Nenhum. O seletor registrado é o mesmo que EX calculava |
| Efeito em ciclos por instrução | Nenhum |

## 2. Validade das instruções à frente

A instrução que está em ID entra em EX na próxima borda, e as três à frente passam a EX/MEM, MEM/WB e WB2. O casamento de cada uma só vale se ela ainda for válida nessa borda, e `core` entrega a `stage_id` as habilitações já condicionadas.

| Instrução à frente | Escreve em registrador e continua válida depois da borda quando |
| :--- | :--- |
| ID/EX (passa a EX/MEM) | $\text{we\_reg} \wedge \text{valid} \wedge \neg\,\text{trap\_sig}$ |
| EX/MEM (passa a MEM/WB) | $\text{we\_reg} \wedge \text{valid}$ |
| MEM/WB (passa a WB2) | `wb_we` |

O descarte de uma instrução à frente por `trap_take` ou por exceção de MEM não entra nas condições, porque o mesmo evento descarta a instrução de ID (`flush_id_ex`), que vira bolha e não usa o seletor. Só `trap_sig`, o sinal de exceção sem efeito do núcleo sem Zicsr, descarta a instrução de EX sem descartar a de ID. Assim os sinais tardios do laço de EX não chegam à entrada do seletor, e o seletor registrado é igual ao que EX calculava com as validades já registradas.

## 3. Verificação

| Garantia | Verificação |
| :--- | :--- |
| O casamento só mantém o destino `x0` fora e respeita as validades | Teste de entidade `ForwardingMatch` e teste de `stage_id` |
| A prioridade entre as fontes é EX/MEM, MEM/WB, WB2 | Teste de entidade `ForwardingUnit`, exaustivo |
| Cada cópia comanda a sua fatia do operando | Teste de `stage_ex` com seletores diferentes por cópia |
| O comportamento do núcleo é o mesmo | Todos os testes de núcleo (`cores/`) com o mesmo número de ciclos e o mesmo conteúdo final da RAM de antes da mudança |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
