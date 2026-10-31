# Arquitetura do Processador RV32 em Pipeline de 5 Estágios

Este documento descreve a organização microarquitetural do processador, a divisão estrutural em cinco estágios, o tratamento de hazards de dados e controle e a integração das extensões `M`, `Zicsr` e `Zifencei`.

![Pipeline Diagram](../img/multi-stage-rv32m_pipeline_final-Pipeline.jpg)

## 1. Visão Geral e Decomposição Estrutural

O processador executa o conjunto de instruções RISC-V de 32 bits em um pipeline em ordem de 5 estágios sincronizados pela borda de subida de um único relógio (`i_clk`). O topo estrutural conecta exclusivamente os cinco estágios e os quatro registradores de barreira temporal:

```
┌──────────┐  reg_if_id  ┌──────────┐  reg_id_ex  ┌──────────┐  reg_ex_mem  ┌───────────┐  reg_mem_wb  ┌──────────┐
│ stage_if │ ──────────► │ stage_id │ ──────────► │ stage_ex │ ───────────► │ stage_mem │ ───────────► │ stage_wb │
└──────────┘             └──────────┘             └──────────┘              └───────────┘              └──────────┘
     ▲                        │                       ▲  ▲                                                  │
     │                        ▼                       │  │                                                  │
     │                  ┌──────────┐       ┌──────────────────────┐                                         │
     │                  │   HDU    │       │   Forwarding Unit    │                                         │
     │                  │ (stall)  │       │  EX/MEM e MEM/WB     │                                         │
     │                  └──────────┘       └──────────────────────┘                                         │
     └───────────────────────────────────────── wb_data / redirecionamento de PC ◄──────────────────────────┘
```

| Camada | Papel arquitetural |
| :--- | :--- |
| Estágio 1 (IF) | Mantém o Program Counter (PC), calcula $\text{PC} + 4$, seleciona a próxima fonte de PC e decodifica a região de busca entre Boot ROM, Flash e cache de instruções externa (SDRAM) |
| Barreira IF/ID | Registra a validade (`o_valid`), o endereço `o_pc`, `o_pc4` e a instrução `o_inst`, respondendo a congelamento (`i_en = '0'`) e descarte (`i_flush = '1'`) |
| Estágio 2 (ID) | Decodifica os sinais de controle da base RV32I e das extensões ativas (`M` e `Zicsr`), estende o imediato de 32 bits, lê os operandos `rs1` e `rs2` no banco de registradores com bypass interno de escrita e detecta conflitos load-use |
| Barreira ID/EX | Registra os operandos lidos, o imediato estendido, os índices `rs1`, `rs2` e `rd` e todos os sinais de controle para execução, memória e write-back |
| Estágio 3 (EX) | Aplica o adiantamento de operandos (forwarding), executa operações na ULA, coordena o multiplicador/divisor multiciclo (`M`), avalia desvios e saltos (`BRANCH`, `JAL`, `JALR`), formata escritas em memória e processa CSRs, exceções e `FENCE.I` |
| Barreira EX/MEM | Registra o resultado final de execução, o dado e a máscara de bytes de store, o índice `rd` e os sinais de controle de memória e write-back |
| Estágio 4 (MEM) | Decodifica o endereço efetivo entre Flash de dados, RAM interna e barramento externo SDRAM/periféricos, gerando o sinal de espera `o_sdram_wait` quando o escravo externo ainda não respondeu |
| Barreira MEM/WB | Registra o resultado de execução `o_alu_out`, o destino `o_rd` e os seletores de extensão de leitura e write-back |
| Estágio 5 (WB) | Seleciona a palavra bruta retornada pela memória acessada, aplica o alinhamento e a extensão de sinal ou zero para bytes e meias-palavras e escolhe o dado final a gravar no banco de registradores |

## 2. Tratamento de Hazards

### 2.1. Adiantamento de Dados (RAW Forwarding)

A unidade de adiantamento no estágio EX compara os registradores fonte da instrução em execução (`i_ex_rs1` e `i_ex_rs2`) com os registradores destino das instruções nos estágios MEM (`i_exmem_rd`) e WB (`i_memwb_rd`) e no registrador WB2 (`i_wb2_rd`), que guarda o dado final de write-back do ciclo anterior. O adiantamento ocorre apenas quando a instrução anterior é válida, habilita escrita em registrador e tem destino diferente de `x0` (`REG_ZERO`).

Quando mais de um desses estágios escreve no mesmo registrador fonte, o mais próximo de EX tem prioridade por conter o valor mais recente na ordem do programa:

| Código (`o_fwd_rs1` / `o_fwd_rs2`) | Fonte selecionada no mux 4x1 de EX | Condição de ativação |
| :--- | :--- | :--- |
| `"00"` | Valor lido do banco de registradores no estágio ID (`i_rs1_val` / `i_rs2_val`) | Nenhuma dependência ativa com MEM ou WB |
| `"10"` | Resultado calculado no estágio EX e registrado em EX/MEM (`i_exmem_alu_out`) | `i_exmem_we_reg = '1'` e `i_exmem_valid = '1'` e `i_exmem_rd = i_ex_rs* /= x0` |
| `"01"` | Resultado de EX registrado em MEM/WB (`i_memwb_alu_out`) | `i_memwb_we_reg = '1'` e `i_memwb_valid = '1'` e `i_memwb_rd = i_ex_rs* /= x0` (sem conflito em EX/MEM) |
| `"11"` | Dado final de write-back registrado em WB2 (`i_wb2_data`) | `i_wb2_we_reg = '1'` e `i_wb2_rd = i_ex_rs* /= x0` (sem conflito em EX/MEM nem em MEM/WB) |

O dado alinhado e estendido de um load só existe no fim do estágio WB, então ele nunca é adiantado de MEM/WB: o adiantamento do load parte do registrador WB2, e a fonte `"01"` só carrega resultados de EX, que já estão registrados. O banco de registradores é escrito a partir de WB2 e tem bypass interno write-through via multiplexadores 2x1 nas portas de leitura `o_rs1` e `o_rs2`, de modo que uma instrução em ID lê o valor escrito por WB2 no mesmo ciclo.

### 2.2. Stall por Conflito Load-Use

Como o dado de um load só chega ao registrador WB2 dois estágios depois de MEM, uma instrução em ID que dependa de um load nos estágios EX (`i_idex_re_ram = '1'` e `i_idex_rd /= x0`) ou MEM (`i_exmem_re_ram = '1'` e `i_exmem_rd /= x0`) precisa aguardar até o load chegar a WB. Isso custa dois ciclos quando a dependência é imediata e um quando há uma instrução entre o load e o dependente:

1. A unidade de detecção de hazards verifica pelo `opcode` da instrução em ID se ela efetivamente lê `rs1` (`OP`, `OP_IMM`, `LOAD`, `STORE`, `BRANCH`, `JALR`, `SYSTEM`) e se efetivamente lê `rs2` (`OP`, `STORE`, `BRANCH`), evitando paradas falsas quando os bits de `rs2` fazem parte do imediato.
2. Quando o conflito é confirmado, a HDU desativa `o_pc_we` e `o_ifid_we` (congelando o PC e o registrador IF/ID) e ativa `o_bubble_sel = '1'`.
3. O multiplexador de bolha (`bubble_mux`) zera os quatro sinais de controle com efeito colateral (`o_we_reg`, `o_we_ram`, `o_re_ram` e `o_en_ram`) e o estágio ID marca `o_idex_valid = '0'`, injetando um `NOP` no registrador ID/EX.

### 2.3. Hazards de Controle e Redirecionamento de PC

A resolução de desvios condicionais, saltos incondicionais, exceções e barreiras `FENCE.I` acontece no estágio EX sob política especulativa *assume-not-taken*. O seletor do próximo PC no estágio IF obedece à seguinte prioridade:

| Prioridade | Código `pc_src` | Fonte do próximo PC | Condição no estágio EX |
| :--- | :--- | :--- | :--- |
| 1 (maior) | `PC_SRC_REDIRECT` (`"11"`) | `i_redirect_pc` (`csr_mepc` em `MRET`, `i_pc4` em `FENCE.I`, ou `csr_mtvec` em trap) | `i_trap_take = '1'` ou `i_mret_take = '1'` ou `i_fencei_take = '1'` |
| 2 | `PC_SRC_JALR` (`"10"`) | `i_jalr_target` = $((\text{rs1} + \text{imm}) \land \texttt{0xFFFFFFFE})$, calculado pela ULA (`ALU_JALR`) | `i_ex_jalr_taken = '1'` (`i_valid = '1'` e `i_opcode = OPCODE_JALR`) |
| 3 | `PC_SRC_BRANCH` (`"01"`) | `i_branch_target` = $\text{PC} + \text{imm}$, calculado pelo somador dedicado de branch | `i_ex_branch_taken = '1'` (`i_valid = '1'` com `OPCODE_JAL` ou `OPCODE_BRANCH` satisfeito) |
| 4 (padrão) | `PC_SRC_PC4` (`"00"`) | $\text{PC} + 4$ | Fluxo sequencial normal |

Quando um desvio ou salto é tomado com o pipeline em avanço (`pipe_run = '1'`), ou quando ocorre trap, `MRET` ou `FENCE.I`, os registradores `reg_if_id` e `reg_id_ex` recebem `i_flush = '1'`, descartando as duas instruções buscadas especulativamente.

### 2.4. Coordenação Global de Stalls Multiciclo

Três condições nos estágios EX e MEM podem pausar o avanço do pipeline:

$$
\begin{aligned}
\text{base\_run} &= \neg (\text{muldiv\_stall} \lor \text{sdram\_wait}) \\
\text{pipe\_run} &= \text{base\_run} \land \neg \text{fencei\_busy} \\
\text{pipe\_stall} &= \text{muldiv\_stall} \lor \text{sdram\_wait} \lor \text{fencei\_busy}
\end{aligned}
$$

- Enquanto `muldiv_stall = '1'` ou `sdram_wait = '1'`, `base_run` vale `'0'`, mantendo congelados `reg_id_ex`, `reg_ex_mem` e `reg_mem_wb`, além do PC e de `reg_if_id` via `pipe_stall` na HDU.
- Enquanto `fencei_busy = '1'` (esperando o término do flush da cache de dados write-back) com `base_run = '1'`, o início do pipeline (`PC`, `IF/ID` e `ID/EX`) permanece retido (`pipe_run = '0'`), `reg_ex_mem` recebe `i_flush = '1'` (injetando bolhas) e `reg_mem_wb` continua avançando para esvaziar acessos pendentes na memória de dados.

## 3. Extensões da ISA

### 3.1. Extensão M (Multiplicação e Divisão Inteira)

Quando `has_m = true`, o decodificador `m_decode` no estágio ID reconhece instruções R-type com `opcode = OPCODE_OP` (`"0110011"`) e `funct7 = FUNCT7_MULDIV` (`"0000001"`), ativando `o_is_muldiv = '1'`, `o_we_reg = '1'` e `o_sel_pc_rs1 = '1'`.

Com `has_zmmul = true` e `has_m = false` (extensão Zmmul), o `m_decode` reconhece só as quatro multiplicações (`funct3(2) = '0'`) e a `multdiv` não instancia o divisor. `DIV`, `DIVU`, `REM` e `REMU` ficam sem dono, e a unidade de controle as trata como instruções ilegais.

No estágio EX, a unidade `multdiv` gera internamente um pulso único de início (`start_pulse`) no primeiro ciclo em que a instrução válida entra em EX, preserva `i_funct3` em um registrador próprio durante toda a operação e aciona o operador correspondente:

| Operador interno | Instruções atendidas | Latência | Tratamento de casos de borda |
| :--- | :--- | :--- | :--- |
| Multiplicador de Booth radix-2 (`booth_multiplier_rv32`) | `MUL`, `MULH`, `MULHSU`, `MULHU` | 33 ciclos (1 init + 32 passos) | A parte alta signed de 32 bits recebe correção pós-multiplicação por somadores de 32 bits para operandos sem sinal (`MULHSU` e `MULHU`) |
| Divisor não-restaurador de 34 bits (`non_restoring_divider_rv32`) | `DIV`, `DIVU`, `REM`, `REMU` | 34 ciclos (caso normal) / 2 ciclos (casos especiais) | Divisão por zero retorna quociente `0xFFFFFFFF` e resto igual ao dividendo; overflow signed ($-2^{31} / -1$) retorna quociente `0x80000000` e resto `0` |

O sinal `o_stall` permanece ativo enquanto o operador está ocupado (`busy = '1'`) e durante o ciclo de pulso de conclusão (`done = '1'`), garantindo que o registrador interno de saída capture o resultado final antes da liberação do pipeline.

### 3.2. Extensão Zicsr e Tratamento de Traps

Quando `has_zicsr = true`, o decodificador `csr_decode` no estágio ID identifica a classe `OPCODE_SYSTEM` (`"1110011"`), força a extração do imediato I-type (`instr[31:20]`) para transportar o endereço de 12 bits do CSR até EX e ativa `o_is_csr = '1'` e `o_we_reg = '1'` para as seis instruções de acesso a CSR (`CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI`).

No estágio EX:

1. O banco `csr_file` lê combinacionalmente o valor atual do CSR (`o_rdata`) e, na borda de subida com `i_commit = i_is_csr and i_valid and i_pipe_run`, atualiza atomicamente o registrador conforme `i_op(1 downto 0)` (`"01"` = escrita direta, `"10"` = set de bits, `"11"` = clear de bits). Nas operações `CSRRS`/`CSRRC` com operando fonte zero (`rs1 = x0` ou `zimm = 0`), nenhuma escrita efetiva é realizada.
2. A unidade `trap_unit` verifica desalinhamento de endereço alvo de salto/branch (`mcause = 0`), instrução `SYSTEM` ou acesso CSR ilegal (`mcause = 2`), `EBREAK` (`mcause = 3`) e `ECALL` (`mcause = 11`), além do retorno `MRET`. Com Zicsr, o endereço efetivo de load (`mcause = 4`) e de store (`mcause = 6`) não é conferido em EX, e sim em MEM, por outra instância da mesma unidade que lê o endereço já registrado em `EX/MEM`.
3. Em caso de exceção (`o_trap_take = '1'`), o registrador `reg_ex_mem` sofre flush para anular os efeitos da instrução faltante, `csr_file` salva o PC em `mepc`, a causa em `mcause`, o valor informativo em `mtval`, move `MIE` para `MPIE`, zera `MIE` e redireciona o PC para `mtvec`.

A exceção de endereço de load ou store é tomada no estágio MEM, no primeiro ciclo em que o acesso chega lá. Como a instrução em MEM é mais antiga que a de EX, a exceção tem prioridade sobre as de EX e descarta a instrução de EX por inteiro: nenhuma escrita de CSR, desvio, `MRET`, `FENCE.I` ou retirada dela tem efeito. O acesso faltante não chega à memória, `MEM/WB` é limpo para que ele não escreva `rd`, e `EX/MEM` carrega o PC e o `funct3` do acesso para o `mepc` e a conferência. A retirada de EX soma em `minstret` um ciclo depois, e a exceção de MEM a cancela, de modo que o acesso que falha não conta como instrução retirada; uma leitura de `instret` já enxerga a retirada pendente.

### 3.3. Extensão Zifencei

Quando `has_zifencei = true`, a unidade `fencei_unit` no estágio EX detecta a instrução `FENCE.I` (`opcode = OPCODE_MISC_MEM` e `funct3 = FUNCT3_FENCE_I`). Sem cache de dados write-back (`has_dcache = false`), ela pulsa `o_take = '1'` imediatamente quando `i_run = '1'`. Com cache de dados (`has_dcache = true`), ela retém a instrução por um ciclo para que os stores anteriores cheguem à cache, requisita o flush (`o_flush_req = '1'`), mantém `o_busy = '1'` até receber `i_dc_done = '1'` e então pulsa `o_take = '1'`, invalidando a cache de instruções externa (`o_ic_inval = '1'`), descartando `IF/ID` e `ID/EX` e redirecionando o PC para $\text{PC} + 4$.

### 3.4. Extensão Zicntr

Quando `has_zicntr = true` (que implica `has_zicsr`), o `csr_file` instancia três contadores de 64 bits, cada um com duas metades de 32 bits e carry registrado entre elas. A leitura soma o carry pendente à metade alta, de modo que `csrr` de `cycleh` logo depois de um estouro da metade baixa já vê o valor correto.

| Contador | Incrementa | Endereços (baixa/alta) | Espelho somente leitura |
| :--- | :--- | :--- | :--- |
| `mcycle` | A cada ciclo de clock do core, inclusive nos ciclos de parada | `0xB00` / `0xB80` | `cycle`: `0xC00` / `0xC80` |
| `minstret` | A cada pulso `i_retire`: instrução válida em EX, pipeline andando, sem exceção | `0xB02` / `0xB82` | `instret`: `0xC02` / `0xC82` |
| `time` | A cada `tick_cycles` ciclos (50 dá 1 MHz a 50 MHz), por um divisor de tick | somente leitura | `time`: `0xC01` / `0xC81` |

`mcycle` e `minstret` aceitam escrita em cada metade; uma escrita vence o incremento do próprio ciclo. Escrever em `cycle`, `time` ou `instret` é acesso ilegal (`mcause = 2`). Sem `has_zicntr` todos esses endereços são desconhecidos e acessá-los é ilegal.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../LICENSE).
