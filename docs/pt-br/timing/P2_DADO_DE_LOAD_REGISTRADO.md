# Passo F.P2: dado de load registrado no fim de WB

## 1. Resumo

| | |
| :--- | :--- |
| Problema | O dado lido da memória passava pelo cruzamento de palavra, pelo alinhamento por byte e pela extensão de sinal em WB, e seguia direto ao adiantamento do estágio EX, à ULA e à decisão de exceção, no mesmo ciclo (6,9 ns do laço de 18,5 ns) |
| Mudança | O dado final de WB é registrado (registrador WB2) e o adiantamento e a escrita no banco de registradores saem desse registrador |
| Efeito no comportamento | Um load seguido de uma instrução que o usa espera um ciclo a mais |
| Hardware | 32 flip-flops de dado, um de escrita e cinco do índice do destino, todos com a habilitação do avanço de MEM/WB |

## 2. Caminho antes e depois

| Etapa | Antes | Depois |
| :--- | :--- | :--- |
| Fontes do adiantamento para EX | EX/MEM, MEM/WB e a saída combinacional de WB | EX/MEM, MEM/WB e o registrador WB2 |
| Ponta do caminho que nasce na leitura da RAM | Leitura, alinhamento, extensão, adiantamento, ULA, exceção, limpeza | Leitura, alinhamento, extensão e o registrador WB2 |
| Escrita do banco de registradores | Saída combinacional de WB | Registrador WB2 |

Com a instrução parada em MEM, a memória síncrona passa a responder ao endereço da instrução parada, então o dado de um load em WB só vale no primeiro ciclo de uma parada; os ciclos seguintes repetem o dado do ciclo anterior (registrador de dado anterior e seu seletor).

## 3. Custo em ciclos por instrução

Uma instrução que depende do load imediatamente anterior espera dois ciclos de parada em vez de um. Sem dependência imediata não há custo. O teste `CoreLoadUse` mede o evento 8 (parada por dependência de load) em duas paradas por par dependente, e o kernel `sdram-load-use` da linha de base (Insper-RISC-V, `docs/pt-br/platform/timing/`) conta uma parada por volta, porque a espera pela cache absorve o outro ciclo.

$$
\text{CPI}_{\text{depois}} = \text{CPI}_{\text{antes}} + f_{\text{load-use}}
$$

em que $f_{\text{load-use}}$ é a fração das instruções que são o uso imediato de um load. O passo só vale se o ganho de frequência superar esse termo, e o critério de aceitação é frequência dividida por CPI.

## 4. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| O dependente de um load recebe o dado alinhado e estendido, em todas as larguras e deslocamentos | Teste `CoreLoadUse` (nove loads, cada um com o uso na instrução seguinte) e testes `CoreMisaligned`, `CoreSdramStall` e `ExtenderRAM` |
| Uma parada em MEM não troca a instrução que o adiantamento vê | Testes `CoreSdramStall` e `CoreLoadStall` (WB2 avança junto de MEM/WB) |
| O dependente espera exatamente dois ciclos, e cada parada é contada uma vez | Testes `CoreLoadUse` e `CoreZihpm` (evento 8) |

## 5. Medição

O RTL deste passo é o da medição de `P1_EXCECAO_DE_ACESSO_EM_MEM.md`, seção 4. O trecho do dado de load (6,9 ns do laço de 18,5 ns antes do passo) não aparece entre os piores caminhos do núcleo: os piores caminhos do núcleo para o núcleo nascem em `ID/EX r_imm`, `EX/MEM r_alu_out` e `EX/MEM r_we_ok` e terminam nos CSRs, nos contadores e no PC, com folga de 3,9 a 5,3 ns a 50 MHz, e nenhum deles passa pelo dado de WB.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
