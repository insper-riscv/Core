# Zicsr: Implementação no Core

Este documento descreve como o Core implementa a extensão `Zicsr` e o tratamento de exceções síncronas do modo máquina que depende dela. As exigências do manual do RISC-V estão em [instructions.md](instructions.md). Os contadores acessados por CSR (`Zicntr` e `Zihpm`) estão documentados em [Zicntr](../Zicntr/description.md) e [Zihpm](../Zihpm/description.md) e não são tratados aqui.

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Capítulo | 5, Zicsr Extension for Control and Status Register (CSR) Instructions, versão 2.0 |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), numeração sem a Introdução |
| Requisitos do manual | [instructions.md](instructions.md) |
| Capítulos do volume privilegiado | 2, Control and Status Registers (CSRs), e 3, Machine-Level ISA, nas seções 3.1.6 a 3.1.16 (CSRs de trap), 3.3 (`ECALL`, `EBREAK`, `MRET`, `WFI`) e a Tabela 17 (prioridade das exceções) |
| Conformidade com o volume privilegiado | `docs/conformance/riscv-privilegiado.md` do Insper-RISC-V |

## 2. Visão Geral

A extensão é ligada pela constante `HAS_ZICSR` do `config_pkg` (padrão `false`) e reúne três blocos.

| Bloco | Estágio | Função |
| :--- | :--- | :--- |
| `csr_decode` | ID | Reconhece a classe `SYSTEM`, marca as seis instruções de acesso a CSR e força a extração do imediato tipo I |
| `csr_file` | EX | Guarda os CSRs, lê o valor antigo e aplica a escrita no fim do ciclo |
| `trap_unit` | EX e MEM | Detecta as exceções síncronas e o retorno `MRET` |

Os pacotes `csr_addr_consts`, `csr_value_consts`, `trap_consts` e `irq_consts` definem os endereços de CSR, os códigos de operação e de `misa`, e as constantes de `ECALL`, `EBREAK`, `MRET`, `WFI` e de `mcause`, além das posições de bit e das causas das interrupções de máquina. O Core implementa apenas o modo máquina, e `mstatus.MPP` lê sempre `11`.

## 3. Decodificação no Estágio ID

O `csr_decode` examina `opcode` e `funct3` da instrução.

| Condição | `o_is_csr` | `o_we_reg` | `o_use_imm_i` |
| :--- | :---: | :---: | :---: |
| `opcode = SYSTEM` e `funct3` diferente de `000` e `100` (as seis instruções CSR) | `1` | `1` | `1` |
| `opcode = SYSTEM` e `funct3` igual a `000` (`ECALL`, `EBREAK`, `MRET`, `WFI`) ou `100` (reservado) | `0` | `0` | `1` |
| Qualquer outro `opcode` | `0` | `0` | `0` |

O sinal `o_use_imm_i` obriga o extensor de imediato a produzir o campo tipo I (`instr[31:20]`), que leva o endereço de 12 bits do CSR (ou o `funct12` das instruções privilegiadas) até o estágio EX. O sinal `o_we_reg` habilita a escrita de `rd` com o valor antigo do CSR. A unidade de detecção de hazards conta `SYSTEM` entre as instruções que leem `rs1`, e insere um ciclo de parada quando um load imediatamente anterior produz esse registrador.

## 4. Execução no Estágio EX

### 4.1. Operando e Ponto de Efetivação

O operando de escrita depende do bit 2 de `funct3`.

| `funct3[2]` | Instruções | Operando $S$ |
| :---: | :--- | :--- |
| `0` | `CSRRW`, `CSRRS`, `CSRRC` | Valor de `rs1` já com adiantamento (forwarding) |
| `1` | `CSRRWI`, `CSRRSI`, `CSRRCI` | Índice de `rs1` (5 bits) estendido com zeros até 32 bits |

A escrita é efetivada na borda de subida do clock em que a instrução é válida em EX e o pipeline avança, conforme a condição abaixo.

$$\text{commit} = \text{is\_csr} \land \text{valid} \land \text{pipe\_run}$$

O valor antigo sai do banco por leitura combinacional e entra no mesmo multiplexador de resultado da ULA e do multiplicador, de modo que atravessa `EX/MEM` e `MEM/WB` e é adiantado como qualquer resultado de ULA, sem ciclos extras. A instrução seguinte lê o CSR já atualizado.

### 4.2. Regras de Escrita

O banco decide a operação pelos bits `[1:0]` de `funct3`.

| `funct3[1:0]` | Operação | Novo valor |
| :---: | :--- | :--- |
| `01` | Escrita | $C' = S$ |
| `10` | Set de bits | $C' = C \lor S$ |
| `11` | Clear de bits | $C' = C \land \lnot S$ |

A fonte é considerada nula quando o campo `rs1` da instrução é `x0` (nas formas imediatas, `uimm = 0`). Uma instrução tem efeito de escrita quando é de escrita (`CSRRW` e `CSRRWI`, mesmo com `rd = x0`) ou quando a fonte não é nula. Com `rs1 = x0`, `CSRRS` e `CSRRC` leem sem escrever e não geram exceção em CSR somente leitura, como exige o manual. O banco sempre lê o CSR, inclusive em `CSRRW` com `rd = x0`; como nenhum CSR do Core tem efeito colateral de leitura, a diferença não é observável.

### 4.3. Acesso Ilegal

O banco sinaliza acesso ilegal quando a expressão abaixo vale.

$$\text{illegal} = \lnot\,\text{endereço\_conhecido} \;\lor\; (\text{tem\_efeito\_de\_escrita} \land \text{addr}[11{:}10] = 11)$$

Um acesso ilegal vira exceção de instrução ilegal (seção 6). Uma escrita só altera o estado quando o endereço é conhecido, o CSR não é somente leitura e o `commit` vale, e nenhum trap, `MRET` ou exceção do estágio MEM ocorre no mesmo ciclo para `mtvec`, `mscratch`, `mepc`, `mcause` e `mtval`.

## 5. Banco de CSRs

Os endereços e os nomes dos CSRs não são escolha do Core. Eles vêm da tabela de CSRs de nível de máquina do manual de arquitetura privilegiada ([Currently allocated RISC-V machine-level CSR addresses](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-4-currently-allocated-risc-v-machine-level-csr-addresses)), e a convenção dos bits do endereço (leitura e escrita nos bits [11:10], privilégio nos bits [9:8]) está na [seção 1.1.1 do mesmo volume](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-1-csr-address-mapping-conventions). A coluna Acesso segue as classes da tabela, com L para `MRO` (somente leitura) e L/E para `MRW` (leitura e escrita), e a coluna Definição leva à seção do manual que descreve cada registrador. O Core implementa só um subconjunto da tabela.

Todos os CSRs valem zero após o reset, exceto `misa` e a parte fixa de `mstatus`, que são constantes. A coluna Escrita descreve o efeito de uma escrita efetiva.

| Endereço | CSR | Acesso | Definição | Leitura | Escrita |
| :---: | :--- | :---: | :---: | :--- | :--- |
| `0x300` | `mstatus` | L/E | [2.1.1.6](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-6-machine-status-mstatus-and-mstatush-registers) | `MPP` (bits 12 e 11) fixo em `11`, `MPIE` (bit 7), `MIE` (bit 3); demais bits zero | Só `MIE` e `MPIE` são gravados; os demais bits são ignorados |
| `0x301` | `misa` | L/E | [2.1.1.1](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#misa) | `0x40000100` (`MXL = 1`, extensão `I`); com `HAS_M`, `0x40001100` (soma o bit 12, extensão `M`); com `IS_BASE_E` verdadeiro (RV32E), o bit 4 (extensão `E`) substitui o bit 8, e o valor é `0x40000010` ou, com `HAS_M`, `0x40001010` | Ignorada |
| `0x304` | `mie` | L/E | [2.1.1.9](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-9-machine-interrupt-mip-and-mie-registers) | Zero; com `HAS_INTERRUPTS`, as máscaras `MSIE`, `MTIE` e `MEIE` (bits 3, 7 e 11) | Com `HAS_INTERRUPTS`, grava os bits 3, 7 e 11; os demais são ignorados |
| `0x305` | `mtvec` | L/E | [2.1.1.7](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-7-machine-trap-vector-base-address-mtvec-register) | `BASE` nos bits `[31:2]` e `MODE` no bit 0 (`0` direto, `1` vetorado); o bit 1 lê zero. Sem `HAS_INTERRUPTS`, `MODE` lê sempre zero | Grava `BASE` e, com `HAS_INTERRUPTS`, `MODE`; no modo vetorado os bits `[5:2]` de `BASE` são gravados em zero (alinhamento de 64 bytes) |
| `0x310` | `mstatush` | L/E | [2.1.1.6](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-6-machine-status-mstatus-and-mstatush-registers) | Zero | Ignorada |
| `0x340` | `mscratch` | L/E | [2.1.1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-13-machine-scratch-mscratch-register) | Valor gravado, 32 bits | Grava os 32 bits |
| `0x341` | `mepc` | L/E | [2.1.1.14](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-14-machine-exception-program-counter-mepc-register) | PC salvo, com os bits `[1:0]` em zero | Grava os bits `[31:2]` |
| `0x342` | `mcause` | L/E | [2.1.1.15](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#mcause) | Código da última exceção, 32 bits | Grava os 32 bits |
| `0x343` | `mtval` | L/E | [2.1.1.16](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-16-machine-trap-value-mtval-register) | Valor associado à última exceção, 32 bits | Grava os 32 bits |
| `0x344` | `mip` | L/E | [2.1.1.9](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-9-machine-interrupt-mip-and-mie-registers) | Zero; com `HAS_INTERRUPTS`, o nível das linhas `MSIP`, `MTIP` e `MEIP` (bits 3, 7 e 11) | Ignorada |
| `0xF11` | `mvendorid` | L | [2.1.1.2](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-2-machine-vendor-id-mvendorid-register) | Zero | Escrita efetiva é ilegal |
| `0xF12` | `marchid` | L | [2.1.1.3](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-3-machine-architecture-id-marchid-register) | Zero | Escrita efetiva é ilegal |
| `0xF13` | `mimpid` | L | [2.1.1.4](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-4-machine-implementation-id-mimpid-register) | Zero | Escrita efetiva é ilegal |
| `0xF14` | `mhartid` | L | [2.1.1.5](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-5-hart-id-mhartid-register) | Zero | Escrita efetiva é ilegal |
| `0xF15` | `mconfigptr` | L | [2.1.1.17](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-17-machine-configuration-pointer-mconfigptr-register) | Zero | Escrita efetiva é ilegal |

Os endereços dos contadores (`mcountinhibit`, `mhpmeventN`, `mcycle`, `minstret`, `mhpmcounterN`, `cycle`, `time`, `instret` e as metades altas) também vêm da tabela do manual privilegiado, e só existem quando o perfil inclui `Zicntr` ou `Zihpm`, descritos em [Zicntr](../Zicntr/description.md) e [Zihpm](../Zihpm/description.md). Sem eles, esses endereços não são conhecidos e o acesso é ilegal. Qualquer outro endereço também não é conhecido. Sem `HAS_INTERRUPTS`, `mie` e `mip` leem zero e ignoram escritas.

### 5.1. Interrupções de Máquina

A constante `HAS_INTERRUPTS` (padrão `false`, exige `HAS_ZICSR`) liga as três linhas de interrupção de máquina do `core` e faz `mip` e `mie` funcionarem. As linhas são de nível e pertencem ao domínio de clock do núcleo; uma fonte em outro domínio passa antes por um `synchronizer` do `Common-Components`.

| Porta | Interrupção | Bit em `mip` e `mie` |
| :--- | :--- | :---: |
| `i_irq_software` | Software de máquina (`MSIP`, `MSIE`) | 3 |
| `i_irq_timer` | Timer de máquina (`MTIP`, `MTIE`) | 7 |
| `i_irq_external` | Externa de máquina (`MEIP`, `MEIE`) | 11 |

O registrador `mip` é somente leitura e lê o nível atual das três linhas nos bits 3, 7 e 11; os demais bits leem zero. Uma escrita em `mip` é legal e não altera nada. O registrador `mie` guarda os bits 3, 7 e 11; os demais bits leem zero e ignoram a escrita, e o valor após o reset é zero. A escrita em `mie` segue as regras gerais da seção 4.2 e não ocorre no ciclo de um trap ou de um `MRET`.

O `csr_file` entrega a decisão de interrupção em três saídas. `o_irq_pending` indica interrupção pendente e habilitada em `mie`, sem considerar `mstatus.MIE`, e `o_irq_take` acrescenta `mstatus.MIE`. `o_irq_cause` traz o `mcause` da interrupção de maior prioridade entre as pendentes e habilitadas.

$$\text{o\_irq\_pending} = \left(\text{mip} \land \text{mie}\right) \ne 0 \qquad \text{o\_irq\_take} = \text{mstatus.MIE} \land \text{o\_irq\_pending}$$

| Pendente e habilitada | `o_irq_cause` |
| :--- | :---: |
| Externa (`MEIP` e `MEIE`) | `0x8000000B` |
| Software (`MSIP` e `MSIE`), sem externa | `0x80000003` |
| Timer (`MTIP` e `MTIE`), sem as duas anteriores | `0x80000007` |
| Estouro de contador (`LCOFIP` e `LCOFIE`, só com Sscofpmf), sem as três anteriores | `0x8000000D` |

A interrupção de estouro de contador pertence à extensão [Sscofpmf](../Sscofpmf/description.md), que acrescenta o bit 13 a `mip` e a `mie`.
Com `HAS_INTERRUPTS = false`, as portas são ignoradas, `mie` e `mip` leem zero e ignoram escritas, `o_irq_pending` e `o_irq_take` valem `0` e `MODE` de `mtvec` lê zero. As posições dos bits e os códigos de `mcause` de cada interrupção ficam no pacote `irq_consts`.

## 6. Exceções Síncronas

### 6.1. Causas Geradas

A `trap_unit` avalia a instrução no estágio EX e sinaliza no máximo uma exceção por instrução, apenas quando a instrução é válida e o pipeline avança.

| `mcause` | Exceção | Condição | `mtval` |
| :---: | :--- | :--- | :--- |
| 0 | Endereço de instrução desalinhado | Desvio, `JAL` ou `JALR` tomado com alvo de bits `[1:0]` diferentes de `00` | Endereço alvo |
| 2 | Instrução ilegal | Encoding indefinido apontado pelo decodificador do estágio ID, instrução `SYSTEM` não suportada, ou acesso a CSR ilegal (seção 4.3) | Zero |
| 3 | Breakpoint | `EBREAK` (`funct12 = 0x001`) | Zero |
| 1 | Falha de acesso de instrução | Busca de instrução fora das regiões executáveis do mapa, com `HAS_ACCESS_FAULTS` (seção 6.7) | PC da instrução |
| 4 | Endereço de load desalinhado | Load desalinhado que o hardware não executa | Endereço efetivo |
| 5 | Falha de acesso de load | Load para endereço que o mapa não aceita ler, com `HAS_ACCESS_FAULTS` (seção 6.7) | Endereço efetivo |
| 6 | Endereço de store desalinhado | Store desalinhado que o hardware não executa | Endereço efetivo |
| 7 | Falha de acesso de store | Store para endereço que o mapa não aceita escrever, com `HAS_ACCESS_FAULTS` (seção 6.7) | Endereço efetivo |
| 11 | Chamada de ambiente do modo máquina | `ECALL` (`funct12 = 0x000`) | Zero |

As instruções `ECALL`, `EBREAK`, `MRET` e `WFI` só são reconhecidas com `funct3 = 000`, `rd = x0` e `rs1 = x0`. Qualquer outra instrução `SYSTEM` que não seja de acesso a CSR, inclusive `funct3 = 100`, `SRET` e `SFENCE.VMA`, é ilegal. O decodificador do estágio ID também marca como ilegal um registrador com índice acima de 15 quando o perfil é RV32E.

Um desalinhamento de load ou store é definido pelas regras da extensão `Zicclsm`: o hardware executa o acesso desalinhado dentro da memória principal (RAM interna e SDRAM) quando `HAS_ZICCLSM = true`, e qualquer outro desalinhamento gera as causas 4 e 6. Com `HAS_ZICSR = true`, essas duas causas são verificadas no estágio MEM por uma segunda instância da `trap_unit`, que lê o endereço efetivo já registrado em `EX/MEM`, e a instância do estágio EX não confere o endereço efetivo.

### 6.2. Prioridade

Para a instância do estágio EX, a prioridade é a da tabela, de cima para baixo.

| Prioridade | `mcause` |
| :---: | :---: |
| 1 | 1 (falha de busca, com `HAS_ACCESS_FAULTS`) |
| 2 | 2 |
| 3 | 0 |
| 4 | 3 |
| 5 | 11 |

A ordem é a da Tabela 17 do volume privilegiado: a instrução ilegal vem antes do endereço de instrução desalinhado. Um `JALR` ou um desvio de codificação reservada com alvo desalinhado gera a causa 2 com `mtval` zero, e só o salto legal gera a causa 0.

A exceção de load ou store (causas 4, 5, 6 e 7) pertence a uma instrução mais antiga que a do estágio EX e por isso tem prioridade sobre todas as causas de EX. Quando ela ocorre, a instrução de EX é descartada por inteiro, sem escrita de CSR, desvio, `MRET`, `FENCE.I` ou retirada.

### 6.3. Entrada no Tratador

Ao tomar uma exceção, o banco de CSRs executa as seguintes ações no mesmo ciclo.

1. `mepc` recebe o PC da instrução faltante, com os dois bits baixos zerados.
2. `mcause` recebe o código da causa e `mtval` recebe o valor associado.
3. `mstatus.MPIE` recebe `mstatus.MIE`, e `mstatus.MIE` vai a zero.
4. O PC passa a valer `mtvec`.

Se a exceção ocorre no estágio MEM, o PC salvo em `mepc` é o da instrução de load ou store, carregado em `EX/MEM`.

### 6.4. Retorno com MRET

A instrução `MRET` (`funct12 = 0x302`) é detectada em EX. Ela restaura `mstatus.MIE` com o valor de `mstatus.MPIE`, grava `mstatus.MPIE` com `1` e redireciona o PC para `mepc`. A instrução `WFI` (`funct12 = 0x105`) é aceita como instrução legal e executa como `NOP` (seção 7.6).

### 6.5. Redirecionamento e Flush

O PC de redirecionamento é escolhido entre `mepc` (em `MRET`), `PC + 4` (em `FENCE.I`), o vetor de `mtvec` (em interrupção com `mtvec` vetorado, seção 7.5) e `BASE` de `mtvec` (nos demais casos). O seletor de PC dá ao redirecionamento a maior prioridade sobre desvios e `JALR`, e o registrador de PC aceita o novo valor mesmo com o pipeline congelado.

| Evento | Registradores esvaziados | Observação |
| :--- | :--- | :--- |
| Exceção ou interrupção em EX | `IF/ID`, `ID/EX`, `EX/MEM` | A instrução faltante ou abortada não escreve `rd` nem acessa a memória |
| Exceção em MEM | `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` | O acesso faltante não chega à memória e a instrução de EX é descartada |
| `MRET` | `IF/ID`, `ID/EX` | A própria `MRET` segue no pipeline como instrução sem efeito em registrador |

### 6.6. Latência

A exceção de EX é detectada de forma combinacional no ciclo em que a instrução está em EX e o pipeline avança. Os CSRs e o PC são gravados na borda de clock que encerra esse ciclo, de modo que a primeira instrução do tratador é buscada no ciclo seguinte. Duas instruções mais novas (nos estágios IF e ID) são descartadas, além da própria instrução faltante. A exceção de load ou store é detectada no ciclo em que o acesso chega a MEM, um ciclo depois da instrução ter passado por EX.

A retirada de uma instrução em EX soma em `minstret` um ciclo depois, e uma exceção de MEM cancela essa soma, de modo que o acesso que falha não conta como retirado. Detalhes dos contadores estão em [Zicntr](../Zicntr/description.md) e [Zihpm](../Zihpm/description.md).

### 6.7. Falhas de Acesso

A constante `HAS_ACCESS_FAULTS` (padrão `false`, exige `HAS_ZICSR`) liga as causas 1, 5 e 7. O mapa válido vem das constantes do mapa de memória do `config_pkg` (`ROM_END`, `RAM_BASE`, `RAM_END`, `EXT_BASE` e `PERIPH_BASE`) e do generic `periph_slots`, a máscara das janelas do barramento de periféricos que têm periférico (bit $n$ para os endereços de bits `ADDR_BITS-2` a `ADDR_BITS-4` iguais a $n$; com `ADDR_BITS = 32`, os bits 30:28 e janelas de 256 MiB), que o `riscv-tools` escreve no pacote do mapa como `PERIPH_SLOTS`. A janela de periféricos começa em `PERIPH_BASE`, `2**(ADDR_BITS - 1)` por padrão. A constante `STRICT_PERIPH` do `config_pkg` (padrão `true`, desligável por plataforma) decide se uma janela sem periférico é recusada: com ela verdadeira o acesso a uma janela vazia gera a falha 5 ou 7; com ela falsa toda janela aceita o acesso. A extensão liga-se pelo `extras: [AccessFaults]` do `platform.yaml`.

| Região | Leitura | Escrita | Busca |
| :--- | :---: | :---: | :---: |
| ROM, de zero a `ROM_END` (BOOT_MEMORY e FLASH) | Sim | Não | Sim |
| RAM, de `RAM_BASE` a `RAM_END` | Sim | Sim | Sim |
| Janela externa, de `EXT_BASE` a `PERIPH_BASE` | Sim | Sim | Sim |
| Janela de periféricos ocupada, a partir de `PERIPH_BASE` | Sim | Sim | Não |
| Janela de periféricos vazia, com `STRICT_PERIPH` | Não | Não | Não |
| Janela de periféricos vazia, sem `STRICT_PERIPH` | Sim | Sim | Não |
| O que sobra (buracos entre as regiões) | Não | Não | Não |

A validade de leitura e de escrita do endereço efetivo é decidida no estágio EX, a partir do resultado da ULA, junto da classificação do endereço que `reg_ex_mem` já registra, e o estágio MEM só confere o bit registrado. A validade da busca sai do PC da instrução em EX, de um registrador, fora do caminho da ULA. Com `HAS_ACCESS_FAULTS = false` as validades valem sempre `1` e nada disso é sintetizado.

A falha de busca vem antes da instrução ilegal, na ordem da Tabela 17 do volume privilegiado. O desalinhamento que o hardware não executa (fora da memória principal) mantém a causa 4 ou 6, a ordem opcional da tabela, e o acesso desalinhado que ele executa só passa se o endereço for válido. Uma falha de load ou store é do endereço da primeira palavra, e o acesso não chega às memórias, como no desalinhamento.

## 7. Tomada de Interrupção

### 7.1. Condição

A `trap_unit` toma a interrupção que o `csr_file` indica em `o_irq_take` sobre a instrução que está em EX. A interrupção só é tomada com instrução válida em EX e pipeline avançando, e nunca sobre `FENCE.I`.

$$\text{toma} = \text{mstatus.MIE} \land \left( (\text{mip} \land \text{mie}) \ne 0 \right) \land \text{valid} \land \text{pipe\_run} \land \lnot\,\text{FENCE.I}$$

Enquanto a condição não vale, a interrupção fica pendente e o programa segue. A linha é de nível, então ela é tomada assim que a condição passa a valer, e o tratador precisa reconhecê-la no periférico antes de retornar.

### 7.2. Prioridade

| Ordem | Evento | `mcause` |
| :---: | :--- | :---: |
| 1 | Interrupção externa de máquina | `0x8000000B` |
| 2 | Interrupção de software de máquina | `0x80000003` |
| 3 | Interrupção de timer de máquina | `0x80000007` |
| 4 | Interrupção de estouro de contador (Sscofpmf) | `0x8000000D` |
| 5 | Exceção síncrona da instrução em EX (seção 6.2) | Código da exceção |

A interrupção tem prioridade sobre a exceção síncrona e sobre o `MRET` da instrução em EX: ela é abortada e fica como a instrução de retorno, e a exceção só ocorre se a instrução for executada depois do retorno. A exceção de load ou store do estágio MEM é de uma instrução mais antiga e vence a interrupção: a instrução de EX é descartada pela exceção, e a interrupção continua pendente até o tratador devolver o controle.

### 7.3. Ponto de Entrada

| Regra | Efeito |
| :--- | :--- |
| `mepc` recebe o PC da instrução em EX | É a primeira instrução que não completou, e o retorno por `MRET` a executa. O porte do FreeRTOS não soma 4 a `mepc` numa interrupção |
| As instruções mais antigas completam | As que estão em MEM e WB terminam normalmente |
| A instrução em EX e as mais novas são descartadas | `IF/ID`, `ID/EX` e `EX/MEM` são esvaziados; nenhuma escrita em registrador, store, escrita de CSR ou `FENCE.I` dessas instruções fica visível |
| `mcause` recebe o código da interrupção, com o bit 31 em `1` | `mtval` recebe zero |
| `mstatus.MPIE` recebe `mstatus.MIE`, e `mstatus.MIE` vai a zero | Igual à exceção síncrona |
| A instrução abortada não conta em `minstret` | Ela conta quando executa depois do retorno |

Uma instrução de acesso a CSR abortada não escreve nada: `mtvec`, `mscratch`, `mie`, os contadores e `mstatus` ficam como estavam, a não ser pelo efeito da própria tomada em `mstatus`, `mepc`, `mcause` e `mtval`.

### 7.4. Casos que Adiam a Tomada

A tomada espera enquanto o pipeline não avança ou não há instrução válida em EX. Nenhum desses casos parte uma instrução ao meio.

| Situação em curso | Efeito |
| :--- | :--- |
| Multiplicação ou divisão | O pipeline fica parado até o término. No ciclo em que o resultado fica pronto a interrupção aborta a instrução, que refaz o cálculo depois do retorno |
| Acesso desalinhado em duas etapas | As duas etapas terminam antes da tomada |
| Espera de leitura ou escrita da SDRAM | O acesso termina antes da tomada |
| Busca esperando `i_ic_ready` | Não há instrução válida em EX; a interrupção é tomada na primeira instrução válida que chega |
| Bolha em EX (salto tomado, dependência de load) | A interrupção é tomada na primeira instrução válida que chega |
| `FENCE.I` em EX | A instrução redireciona o pipeline para a seguinte e completa; a interrupção é tomada nessa seguinte |

Uma linha que sobe de novo antes de a primeira instrução do programa retirar refaz a mesma entrada sem fim. Por isso o intervalo entre interrupções precisa exceder a duração do tratador somada à da instrução mais longa do programa, que é a divisão.

### 7.5. Modos de `mtvec`

| `MODE` (bit 0) | Destino de uma interrupção | Destino de uma exceção síncrona |
| :---: | :--- | :--- |
| `0` (direto) | `BASE` | `BASE` |
| `1` (vetorado) | $\text{BASE} + 4 \times \text{causa}$ | `BASE` |

Os modos `2` e `3` são reservados, e o bit 1 lê zero. No modo vetorado `BASE` tem alinhamento de 64 bytes, pois a maior causa de interrupção implementada é 11 e a tabela ocupa 16 entradas de 4 bytes. Com esse alinhamento a soma é a troca dos bits `[5:2]` de `BASE` pelos quatro bits baixos da causa, sem somador. A `ECALL` tem causa 11 e vai a `BASE`, porque o vetor vale só para interrupção.

| Causa | Posição na tabela |
| :---: | :---: |
| 3 (software) | `BASE + 12` |
| 7 (timer) | `BASE + 28` |
| 11 (externa) | `BASE + 44` |

### 7.6. MRET e WFI

O `MRET` segue a seção 6.4. A `WFI` executa como `NOP`, como o manual privilegiado permite, então o núcleo não para à espera de interrupção. Uma interrupção tomada sobre a `WFI` devolve o controle à própria `WFI`, que executa como `NOP` no retorno.

## 8. Core sem Zicsr

Com `HAS_ZICSR = false`, o `csr_file` e o `csr_decode` não são instanciados e não há registradores de trap. O Core mantém um detector de causas que apenas sinaliza a exceção nas saídas e não redireciona o PC.

| Saída | Valor |
| :--- | :--- |
| `o_trap` | Pulso de um ciclo em `1` quando uma exceção ocorre; fica em `0` com Zicsr |
| `o_trap_cause` | Código de causa no formato de `mcause`; fica em zero com Zicsr |
| `o_trap_pc` | PC da instrução que gerou a exceção; fica em zero com Zicsr |
| `o_trap_take` | Pulso de um ciclo em `1` quando o Core toma uma exceção síncrona, com ou sem Zicsr |

Nesse modo, toda instrução de acesso a CSR é ilegal (causa 2), `ECALL` gera a causa 11 e `EBREAK` a causa 3, e o desalinhamento de load e store (causas 4 e 6) é conferido no próprio estágio EX. O desalinhamento do alvo de desvio não é conferido, e `MRET` não tem efeito. A instrução faltante é anulada em EX, sem escrita em `rd` e sem acesso à memória, e o programa segue na instrução seguinte. A instrução que gerou a exceção não conta como retirada. O ambiente em volta do Core decide o que fazer com o sinal.

A saída `o_trap_take` existe nos dois modos. Com Zicsr, ela pulsa no ciclo em que o Core desvia o PC para `mtvec`, quando `o_trap` fica em `0`, e é o sinal que um topo de síntese usa para mostrar a exceção, por exemplo num LED. Sem Zicsr, ela pulsa junto de `o_trap`. A interrupção de máquina, ao ser tomada, também deve pulsar `o_trap_take`.

Um perfil exige `Zicsr` ou `Zicclsm`, porque sem os dois um acesso desalinhado não teria trap nem execução em hardware, e a elaboração falha. `Zicntr` e `Zihpm` exigem `Zicsr`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
