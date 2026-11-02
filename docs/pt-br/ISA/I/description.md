# RV32I: Implementação no Core

Este documento descreve como o Core implementa a base inteira RV32I. Os requisitos do manual do RISC-V estão em [instructions.md](instructions.md), e a microarquitetura completa do pipeline em [ARCHITECTURE.md](../../ARCHITECTURE.md).

## 1. Módulos da Base

| Módulo | Pasta | Responsabilidade |
| :--- | :--- | :--- |
| `alu` | `src/I/` | Operações inteiras, endereço efetivo, alvo de `JALR` e condição de desvio ([ULA.md](ULA.md)) |
| `extender_imm` | `src/I/` | Monta o imediato de 32 bits de cada formato |
| `extender_ram` | `src/I/` | Seleciona e estende o byte ou a meia-palavra lida por um load |
| `store_manager` | `src/I/` | Posiciona o dado de um store na palavra e gera a máscara de bytes |
| `control_unit` | `src/shared/` | Decodifica `opcode`, `funct3` e `funct7` nos sinais de controle ([DECODER.md](DECODER.md)) e detecta instrução ilegal |
| `reg_file` | `src/shared/` | Banco de registradores com duas portas de leitura e uma de escrita |
| `pc_fetch` | `src/shared/` | Registrador do `pc`, soma $\text{pc} + 4$ e seleção do próximo `pc` |
| `forwarding_unit` e `hazard_detection_unit` | `src/shared/` | Adiantamento de operandos e parada por dependência de load |
| `stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb` | `src/core/` | Os cinco estágios do pipeline |

## 2. Distribuição das Instruções pelos Estágios

| Estágio | O que a base RV32I faz |
| :--- | :--- |
| IF | Busca a instrução no `pc` e escolhe o próximo `pc` entre $\text{pc} + 4$, o alvo de desvio ou `JAL`, o alvo de `JALR` e o redirecionamento de trap |
| ID | Decodifica os sinais de controle, estende o imediato, lê `rs1` e `rs2` no banco de registradores e detecta a dependência de load |
| EX | Aplica o adiantamento aos operandos, executa a ULA, calcula $\text{pc} + \text{imm}$ no somador de desvio, avalia a condição de desvio e formata o dado e a máscara de bytes dos stores |
| MEM | Envia o endereço efetivo, o dado e a máscara à memória certa e espera a resposta quando o escravo é lento |
| WB | Alinha e estende a palavra lida por um load, escolhe entre ela e o resultado da ULA e grava em `rd` |

## 3. Unidade de Controle

A unidade de controle é combinacional. Seus sinais partem de valores padrão que formam um `NOP` (sem escrita em registrador nem acesso à memória) e cada `opcode` os sobrescreve. A tabela completa por instrução está em [DECODER.md](DECODER.md); a tabela abaixo resume o papel dos sinais.

| Sinal | Função |
| :--- | :--- |
| `o_sel_pc_rs1` | Operando A da ULA, `rs1` quando `1` e `pc` quando `0` (`AUIPC`, `JAL`, `LUI`) |
| `o_sel_rs2_imm` | Operando B da ULA, imediato quando `1` e `rs2` quando `0` |
| `o_sel_pc4_alu` | Seleciona $\text{pc} + 4$ como resultado de EX em `JAL` e `JALR` |
| `o_ext_imm_op` | Formato do imediato (U, I, I com `shamt`, S, B ou J) |
| `o_alu_op` | Código de 5 bits da operação da ULA |
| `o_we_reg` | Habilita a escrita em `rd` |
| `o_wb_sel` | Origem do dado gravado, ULA (`WB_SEL_ALU`) ou memória (`WB_SEL_RAM`) |
| `o_re_ram`, `o_we_ram`, `o_en_ram` | Leitura, escrita e habilitação do acesso à memória de dados |
| `o_ext_ram_op` | Largura e extensão do load (`LB`, `LH`, `LW`, `LBU`, `LHU`) |

Um segundo processo calcula `o_illegal`. A palavra é legal quando os bits 1 e 0 valem `11` e a combinação de `opcode`, `funct3` e `funct7` é uma das aceitas na seção 8 de [instructions.md](instructions.md). `FENCE` e as instruções SYSTEM são legais nesse processo, e o detector de exceções da extensão Zicsr decide depois quais SYSTEM são válidas.

## 4. Imediatos

O extensor de imediato escolhe o formato por `o_ext_imm_op`.

| Operação | Imediato de 32 bits |
| :--- | :--- |
| `EXT_IMM_U` | $\text{inst}[31{:}12] \,\Vert\, 0^{12}$ |
| `EXT_IMM_I` | $\text{sext}(\text{inst}[31{:}20])$ |
| `EXT_IMM_I_SHAMT` | $0^{27} \,\Vert\, \text{inst}[24{:}20]$ |
| `EXT_IMM_S` | $\text{sext}(\text{inst}[31{:}25] \,\Vert\, \text{inst}[11{:}7])$ |
| `EXT_IMM_B` | $\text{sext}(\text{inst}[31] \,\Vert\, \text{inst}[7] \,\Vert\, \text{inst}[30{:}25] \,\Vert\, \text{inst}[11{:}8] \,\Vert\, 0)$ |
| `EXT_IMM_J` | $\text{sext}(\text{inst}[31] \,\Vert\, \text{inst}[19{:}12] \,\Vert\, \text{inst}[20] \,\Vert\, \text{inst}[30{:}21] \,\Vert\, 0)$ |

Qualquer outro código produz zero. Nas instruções SYSTEM o estágio ID força o formato I, porque o detector de exceções lê o campo `funct12` pelo imediato.

## 5. Desvios e Saltos

Os desvios e saltos são resolvidos em EX, sob a política de assumir desvio não tomado.

| Instrução | Alvo | Condição |
| :--- | :--- | :--- |
| `JAL` | $\text{pc} + \text{imm}_J$, no somador de desvio | Sempre tomado |
| `JALR` | $(x[rs1] + \text{imm}_I) \land \texttt{0xFFFFFFFE}$, na ULA | Sempre tomado |
| `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` | $\text{pc} + \text{imm}_B$, no somador de desvio | `o_branch` da ULA |

`JAL` e `JALR` gravam $\text{pc} + 4$ em `rd` pelo caminho normal do resultado de EX. Quando um desvio ou salto é tomado, os registradores IF/ID e ID/EX são descartados, o que custa dois ciclos. O seletor de `pc` e sua prioridade estão em [ARCHITECTURE.md](../../ARCHITECTURE.md), seção 2.3.

## 6. Acesso à Memória de Dados

O endereço efetivo $x[rs1] + \text{imm}$ sai da ULA com a operação de soma. Os dois bits baixos dele escolhem a faixa de bytes.

### 6.1. Stores

O gerenciador de stores, em EX, replica a posição do dado e gera a máscara de bytes. A máscara é nula quando a instrução não é um store.

| Instrução | Dado na palavra | Máscara de bytes por deslocamento (0, 1, 2, 3) |
| :--- | :--- | :--- |
| `SW` | $x[rs2]$ inteiro | `1111` em todos |
| `SH` | $x[rs2][15{:}0]$ deslocado de $8 \cdot \text{offset}$ bits (16 bits para o deslocamento 3) | `0011`, `0110`, `1100`, `1100` |
| `SB` | $x[rs2][7{:}0]$ deslocado de $8 \cdot \text{offset}$ bits | `0001`, `0010`, `0100`, `1000` |

No deslocamento 3 de `SH`, o acesso cruza a palavra e seu tratamento está em [ACESSO_DESALINHADO.md](../../ACESSO_DESALINHADO.md). O mesmo vale para `SW` com deslocamento diferente de 0.

### 6.2. Loads

O extensor de leitura, em WB, recebe a palavra lida e o deslocamento de bytes.

| Instrução | Resultado |
| :--- | :--- |
| `LW` | A palavra inteira |
| `LH` | Meia-palavra da faixa escolhida, com extensão de sinal |
| `LHU` | Meia-palavra da faixa escolhida, com extensão de zero |
| `LB` | Byte da faixa escolhida, com extensão de sinal |
| `LBU` | Byte da faixa escolhida, com extensão de zero |

O dado final de um load só existe ao fim de WB. Por isso o adiantamento de um load parte do registrador WB2, e não de MEM/WB. Acessos desalinhados, a largura da memória e as regiões do mapa têm documentos próprios ([ACESSO_DESALINHADO.md](../../ACESSO_DESALINHADO.md) e [LARGURA_DA_MEMORIA.md](../../LARGURA_DA_MEMORIA.md)).

## 7. Banco de Registradores

| Característica | Comportamento |
| :--- | :--- |
| Portas | Duas de leitura (`rs1`, `rs2`) e uma de escrita (`rd`) |
| `x0` | Constante zero, sem registrador; a escrita nunca o habilita |
| Reset | Assíncrono, nos registradores `x1` a `x31` |
| Leitura no ciclo da escrita | Um multiplexador entrega o dado que está sendo escrito quando o registrador lido é o mesmo, exceto `x0` |
| Tamanho | 32 registradores; o genérico `num_regs` igual a 16 seleciona o RV32E ([RV32E.md](../../RV32E.md)) |

## 8. Adiantamento e Hazards

| Situação | Tratamento | Custo | Detalhe |
| :--- | :--- | :--- | :--- |
| Dependência de dados entre instruções próximas | Adiantamento para os operandos de EX a partir de EX/MEM, MEM/WB e WB2, com prioridade ao estágio mais próximo de EX; `x0` nunca é adiantado | Nenhum | [ARCHITECTURE.md](../../ARCHITECTURE.md), seção 2.1 |
| Uso do resultado de um load | Parada de ID com bolha em ID/EX | 2 ciclos se a dependência é imediata, 1 se há uma instrução entre os dois | [ARCHITECTURE.md](../../ARCHITECTURE.md), seção 2.2 |
| Desvio ou salto tomado | Descarte de IF/ID e ID/EX | 2 ciclos | [ARCHITECTURE.md](../../ARCHITECTURE.md), seção 2.3 |
| Espera de memória lenta | Congelamento global do pipeline | Tempo de espera | [ARCHITECTURE.md](../../ARCHITECTURE.md), seção 2.4 |

## 9. Genéricos que Afetam a Base

| Genérico | Efeito sobre a base RV32I |
| :--- | :--- |
| `num_regs` | 32 ou 16 registradores; no valor 16, a instrução que usa `x16` a `x31` é ilegal |
| `has_zicsr` | Ativa a exceção síncrona (ilegal, `ECALL`, `EBREAK`, alvo desalinhado) com redirecionamento para `mtvec`; desativado, o Core apenas sinaliza `o_trap` |
| `has_zicclsm` | Executa em hardware os loads e stores desalinhados da memória principal; desativado, todo acesso desalinhado gera exceção |
| `has_zifencei` | Torna `FENCE.I` legal; `FENCE` é sempre legal |

## 10. Casos Limite

| Caso | Comportamento |
| :--- | :--- |
| Escrita com `rd` igual a `x0` | Descartada; o adiantamento a ignora |
| Load com `rd` igual a `x0` | O acesso à memória e a verificação de alinhamento ocorrem; o resultado não é gravado |
| `JALR` com bit 0 do alvo em 1 | O bit 0 é zerado antes de usar o alvo |
| Alvo com bit 1 em 1 | Exceção de causa 0 com Zicsr; sem Zicsr não há verificação |
| Deslocamento por registrador | Usa só os 5 bits baixos de `rs2` |
| `SLLI`, `SRLI` ou `SRAI` com `funct7` inválido | Instrução ilegal |
| `FENCE` com campos reservados | Executa como `NOP` |
| Palavra desconhecida | Sinais de `NOP` e `o_illegal` em `1` |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
