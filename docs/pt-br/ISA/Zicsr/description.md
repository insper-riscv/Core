# Zicsr: Implementação no Core

Este documento descreve como o Core implementa a extensão `Zicsr` e o tratamento de exceções síncronas do modo máquina que depende dela. As exigências do manual do RISC-V estão em [instructions.md](instructions.md). Os contadores acessados por CSR (`Zicntr` e `Zihpm`) estão documentados em [../Zicntr_Zihpm/](../Zicntr_Zihpm/) e não são tratados aqui.

## 1. Visão Geral

A extensão é ligada pelo generic `has_zicsr` da entidade `core` (padrão `false`) e reúne três blocos.

| Bloco | Estágio | Função |
| :--- | :--- | :--- |
| `csr_decode` | ID | Reconhece a classe `SYSTEM`, marca as seis instruções de acesso a CSR e força a extração do imediato tipo I |
| `csr_file` | EX | Guarda os CSRs, lê o valor antigo e aplica a escrita no fim do ciclo |
| `trap_unit` | EX e MEM | Detecta as exceções síncronas e o retorno `MRET` |

Os pacotes `csr_addr_consts`, `csr_value_consts` e `trap_consts` definem os endereços de CSR, os códigos de operação e de `misa`, e as constantes de `ECALL`, `EBREAK`, `MRET`, `WFI` e de `mcause`. O Core implementa apenas o modo máquina, e `mstatus.MPP` lê sempre `11`.

## 2. Decodificação no Estágio ID

O `csr_decode` examina `opcode` e `funct3` da instrução.

| Condição | `o_is_csr` | `o_we_reg` | `o_use_imm_i` |
| :--- | :---: | :---: | :---: |
| `opcode = SYSTEM` e `funct3` diferente de `000` e `100` (as seis instruções CSR) | `1` | `1` | `1` |
| `opcode = SYSTEM` e `funct3` igual a `000` (`ECALL`, `EBREAK`, `MRET`, `WFI`) ou `100` (reservado) | `0` | `0` | `1` |
| Qualquer outro `opcode` | `0` | `0` | `0` |

O sinal `o_use_imm_i` obriga o extensor de imediato a produzir o campo tipo I (`instr[31:20]`), que leva o endereço de 12 bits do CSR (ou o `funct12` das instruções privilegiadas) até o estágio EX. O sinal `o_we_reg` habilita a escrita de `rd` com o valor antigo do CSR. A unidade de detecção de hazards conta `SYSTEM` entre as instruções que leem `rs1`, e insere um ciclo de parada quando um load imediatamente anterior produz esse registrador.

## 3. Execução no Estágio EX

### 3.1. Operando e Ponto de Efetivação

O operando de escrita depende do bit 2 de `funct3`.

| `funct3[2]` | Instruções | Operando $S$ |
| :---: | :--- | :--- |
| `0` | `CSRRW`, `CSRRS`, `CSRRC` | Valor de `rs1` já com adiantamento (forwarding) |
| `1` | `CSRRWI`, `CSRRSI`, `CSRRCI` | Índice de `rs1` (5 bits) estendido com zeros até 32 bits |

A escrita é efetivada na borda de subida do clock em que a instrução é válida em EX e o pipeline avança, conforme a condição abaixo.

$$\text{commit} = \text{is\_csr} \land \text{valid} \land \text{pipe\_run}$$

O valor antigo sai do banco por leitura combinacional e entra no mesmo multiplexador de resultado da ULA e do multiplicador, de modo que atravessa `EX/MEM` e `MEM/WB` e é adiantado como qualquer resultado de ULA, sem ciclos extras. A instrução seguinte lê o CSR já atualizado.

### 3.2. Regras de Escrita

O banco decide a operação pelos bits `[1:0]` de `funct3`.

| `funct3[1:0]` | Operação | Novo valor |
| :---: | :--- | :--- |
| `01` | Escrita | $C' = S$ |
| `10` | Set de bits | $C' = C \lor S$ |
| `11` | Clear de bits | $C' = C \land \lnot S$ |

A fonte é considerada nula quando o campo `rs1` da instrução é `x0` (nas formas imediatas, `uimm = 0`). Uma instrução tem efeito de escrita quando é de escrita (`CSRRW` e `CSRRWI`, mesmo com `rd = x0`) ou quando a fonte não é nula. Com `rs1 = x0`, `CSRRS` e `CSRRC` leem sem escrever e não geram exceção em CSR somente leitura, como exige o manual. O banco sempre lê o CSR, inclusive em `CSRRW` com `rd = x0`; como nenhum CSR do Core tem efeito colateral de leitura, a diferença não é observável.

### 3.3. Acesso Ilegal

O banco sinaliza acesso ilegal quando a expressão abaixo vale.

$$\text{illegal} = \lnot\,\text{endereço\_conhecido} \;\lor\; (\text{tem\_efeito\_de\_escrita} \land \text{addr}[11{:}10] = 11)$$

Um acesso ilegal vira exceção de instrução ilegal (seção 5). Uma escrita só altera o estado quando o endereço é conhecido, o CSR não é somente leitura e o `commit` vale, e nenhum trap, `MRET` ou exceção do estágio MEM ocorre no mesmo ciclo para `mtvec`, `mscratch`, `mepc`, `mcause` e `mtval`.

## 4. Banco de CSRs

Todos os CSRs valem zero após o reset, exceto `misa` e a parte fixa de `mstatus`, que são constantes. A coluna Acesso indica se uma escrita efetiva é aceita, e a coluna Escrita descreve o efeito.

| Endereço | CSR | Acesso | Leitura | Escrita |
| :---: | :--- | :---: | :--- | :--- |
| `0x300` | `mstatus` | L/E | `MPP` (bits 12 e 11) fixo em `11`, `MPIE` (bit 7), `MIE` (bit 3); demais bits zero | Só `MIE` e `MPIE` são gravados; os demais bits são ignorados |
| `0x301` | `misa` | L/E | `0x40000100` (`MXL = 1`, extensão `I`); com `has_m`, `0x40001100` (soma o bit 12, extensão `M`) | Ignorada |
| `0x304` | `mie` | L/E | Zero | Ignorada |
| `0x305` | `mtvec` | L/E | Endereço base do tratador, com os bits `[1:0]` em zero | Grava os bits `[31:2]`; o modo é sempre direto |
| `0x310` | `mstatush` | L/E | Zero | Ignorada |
| `0x340` | `mscratch` | L/E | Valor gravado, 32 bits | Grava os 32 bits |
| `0x341` | `mepc` | L/E | PC salvo, com os bits `[1:0]` em zero | Grava os bits `[31:2]` |
| `0x342` | `mcause` | L/E | Código da última exceção, 32 bits | Grava os 32 bits |
| `0x343` | `mtval` | L/E | Valor associado à última exceção, 32 bits | Grava os 32 bits |
| `0x344` | `mip` | L/E | Zero | Ignorada |
| `0xF11` | `mvendorid` | L | Zero | Escrita efetiva é ilegal |
| `0xF12` | `marchid` | L | Zero | Escrita efetiva é ilegal |
| `0xF13` | `mimpid` | L | Zero | Escrita efetiva é ilegal |
| `0xF14` | `mhartid` | L | Zero | Escrita efetiva é ilegal |
| `0xF15` | `mconfigptr` | L | Zero | Escrita efetiva é ilegal |

Os endereços dos contadores (`mcountinhibit`, `mhpmeventN`, `mcycle`, `minstret`, `mhpmcounterN`, `cycle`, `time`, `instret` e as metades altas) só existem quando o perfil inclui `Zicntr` ou `Zihpm`. Sem eles, esses endereços não são conhecidos e o acesso é ilegal. Qualquer outro endereço também não é conhecido. Como o Core não tem interrupções, `mie` e `mip` leem zero e ignoram escritas.

## 5. Exceções Síncronas

### 5.1. Causas Geradas

A `trap_unit` avalia a instrução no estágio EX e sinaliza no máximo uma exceção por instrução, apenas quando a instrução é válida e o pipeline avança.
| `mcause` | Exceção | Condição | `mtval` |
| :---: | :--- | :--- | :--- |
| 0 | Endereço de instrução desalinhado | Desvio, `JAL` ou `JALR` tomado com alvo de bits `[1:0]` diferentes de `00` | Endereço alvo |
| 2 | Instrução ilegal | Encoding indefinido apontado pelo decodificador do estágio ID, instrução `SYSTEM` não suportada, ou acesso a CSR ilegal (seção 3.3) | Zero |
| 3 | Breakpoint | `EBREAK` (`funct12 = 0x001`) | Zero |
| 4 | Endereço de load desalinhado | Load desalinhado que o hardware não executa | Endereço efetivo |
| 6 | Endereço de store desalinhado | Store desalinhado que o hardware não executa | Endereço efetivo |
| 11 | Chamada de ambiente do modo máquina | `ECALL` (`funct12 = 0x000`) | Zero |

As instruções `ECALL`, `EBREAK`, `MRET` e `WFI` só são reconhecidas com `funct3 = 000`, `rd = x0` e `rs1 = x0`. Qualquer outra instrução `SYSTEM` que não seja de acesso a CSR, inclusive `funct3 = 100`, `SRET` e `SFENCE.VMA`, é ilegal. O decodificador do estágio ID também marca como ilegal um registrador com índice acima de 15 quando o perfil é RV32E.

Um desalinhamento de load ou store é definido pelas regras da extensão `Zicclsm`: o hardware executa o acesso desalinhado dentro da memória principal (RAM interna e SDRAM) quando `has_zicclsm = true`, e qualquer outro desalinhamento gera as causas 4 e 6. Com `has_zicsr = true`, essas duas causas são verificadas no estágio MEM por uma segunda instância da `trap_unit`, que lê o endereço efetivo já registrado em `EX/MEM`, e a instância do estágio EX não confere o endereço efetivo.

### 5.2. Prioridade

Para a instância do estágio EX, a prioridade é a da tabela, de cima para baixo.

| Prioridade | `mcause` |
| :---: | :---: |
| 1 | 0 |
| 2 | 2 |
| 3 | 3 |
| 4 | 11 |

A exceção de load ou store (causas 4 e 6) pertence a uma instrução mais antiga que a do estágio EX e por isso tem prioridade sobre todas as causas de EX. Quando ela ocorre, a instrução de EX é descartada por inteiro, sem escrita de CSR, desvio, `MRET`, `FENCE.I` ou retirada.

### 5.3. Entrada no Tratador

Ao tomar uma exceção, o banco de CSRs executa as seguintes ações no mesmo ciclo.

1. `mepc` recebe o PC da instrução faltante, com os dois bits baixos zerados.
2. `mcause` recebe o código da causa e `mtval` recebe o valor associado.
3. `mstatus.MPIE` recebe `mstatus.MIE`, e `mstatus.MIE` vai a zero.
4. O PC passa a valer `mtvec`.

Se a exceção ocorre no estágio MEM, o PC salvo em `mepc` é o da instrução de load ou store, carregado em `EX/MEM`.

### 5.4. Retorno com MRET

A instrução `MRET` (`funct12 = 0x302`) é detectada em EX. Ela restaura `mstatus.MIE` com o valor de `mstatus.MPIE`, grava `mstatus.MPIE` com `1` e redireciona o PC para `mepc`. A instrução `WFI` (`funct12 = 0x105`) é aceita como instrução legal e não faz nada.

### 5.5. Redirecionamento e Flush

O PC de redirecionamento é escolhido entre `mepc` (em `MRET`), `PC + 4` (em `FENCE.I`) e `mtvec` (em exceção). O seletor de PC dá ao redirecionamento a maior prioridade sobre desvios e `JALR`, e o registrador de PC aceita o novo valor mesmo com o pipeline congelado.

| Evento | Registradores esvaziados | Observação |
| :--- | :--- | :--- |
| Exceção em EX | `IF/ID`, `ID/EX`, `EX/MEM` | A instrução faltante não escreve `rd` nem acessa a memória |
| Exceção em MEM | `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` | O acesso faltante não chega à memória e a instrução de EX é descartada |
| `MRET` | `IF/ID`, `ID/EX` | A própria `MRET` segue no pipeline como instrução sem efeito em registrador |

### 5.6. Latência

A exceção de EX é detectada de forma combinacional no ciclo em que a instrução está em EX e o pipeline avança. Os CSRs e o PC são gravados na borda de clock que encerra esse ciclo, de modo que a primeira instrução do tratador é buscada no ciclo seguinte. Duas instruções mais novas (nos estágios IF e ID) são descartadas, além da própria instrução faltante. A exceção de load ou store é detectada no ciclo em que o acesso chega a MEM, um ciclo depois da instrução ter passado por EX.

A retirada de uma instrução em EX soma em `minstret` um ciclo depois, e uma exceção de MEM cancela essa soma, de modo que o acesso que falha não conta como retirado. Detalhes dos contadores estão em [../Zicntr_Zihpm/](../Zicntr_Zihpm/).

## 6. Core sem Zicsr

Com `has_zicsr = false`, o `csr_file` e o `csr_decode` não são instanciados e não há registradores de trap. O Core mantém um detector de causas que apenas sinaliza a exceção nas saídas e não redireciona o PC.

| Saída | Valor |
| :--- | :--- |
| `o_trap` | Pulso de um ciclo em `1` quando uma exceção ocorre; fica em `0` com Zicsr |
| `o_trap_cause` | Código de causa no formato de `mcause`; fica em zero com Zicsr |
| `o_trap_pc` | PC da instrução que gerou a exceção; fica em zero com Zicsr |

Nesse modo, toda instrução de acesso a CSR é ilegal (causa 2), `ECALL` gera a causa 11 e `EBREAK` a causa 3, e o desalinhamento de load e store (causas 4 e 6) é conferido no próprio estágio EX. O desalinhamento do alvo de desvio não é conferido, e `MRET` não tem efeito. A instrução faltante é anulada em EX, sem escrita em `rd` e sem acesso à memória, e o programa segue na instrução seguinte. A instrução que gerou a exceção não conta como retirada. O ambiente em volta do Core decide o que fazer com o sinal.

Um perfil exige `Zicsr` ou `Zicclsm`, porque sem os dois um acesso desalinhado não teria trap nem execução em hardware, e a elaboração falha. `Zicntr` e `Zihpm` exigem `Zicsr`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
