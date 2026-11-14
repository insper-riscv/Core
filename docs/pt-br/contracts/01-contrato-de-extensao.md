# 1. Contrato de Extensão do Pipeline RV32

## 1. Escopo do Contrato

A especificação RISC-V define a semântica arquitetural de cada instrução (opcodes, campos `funct3`/`funct7` e efeito nos registradores). O contrato de extensão define como o hardware de uma extensão (`M/`, `Zicsr/`, `Zifencei/`) se conecta aos estágios do pipeline (`core/`) sem acoplar a lógica base (`common/` e `I/`) aos detalhes internos de cada extensão.

Cada extensão reside em sua própria pasta e é habilitada no topo `src/core/core.vhd` por uma constante booleana do `config_pkg` (`HAS_M`, `HAS_ZMMUL`, `HAS_ZICSR`, `HAS_ZIFENCEI`, `HAS_ZICOND`, `HAS_DCACHE`). Quando a constante correspondente vale `false`, as instruções daquela extensão comportam-se como `NOP` (sem escrita em registrador, sem acesso à memória e sem parada do pipeline).

Os estágios instanciam as unidades de cada extensão diretamente por `entity work`, sem declaração `component`. Por isso todo perfil analisa os arquivos de todas as extensões, e a constante em `false` retira a unidade da elaboração.

## 2. Regras de Integração no Pipeline

### 2.1. Decodificação no Estágio ID

A unidade de controle base (`src/shared/control_unit.vhd`) decodifica exclusivamente o conjunto RV32I. Instruções de extensões opcionais são reivindicadas por decodificadores dedicados instanciados condicionalmente em `src/core/stage_id.vhd`:

| Extensão | Decodificador em `stage_id` | Condição de reivindicação | Sinais ativados |
| :--- | :--- | :--- | :--- |
| `M` | `src/M/m_decode.vhd` | `opcode = OPCODE_OP` (`"0110011"`) e `funct7 = FUNCT7_MULDIV` (`"0000001"`) | `o_is_muldiv = '1'`, `o_we_reg = '1'`, `o_sel_pc_rs1 = '1'` |
| `Zicond` | `src/Zicond/zicond_decode.vhd` | `opcode = OPCODE_OP` (`"0110011"`), `funct7 = FUNCT7_ZICOND` (`"0000111"`) e `funct3` igual a `"101"` ou `"111"` | `o_is_zicond = '1'`, `o_we_reg = '1'`, `o_sel_pc_rs1 = '1'` e `o_alu_op` com o código da instrução |
| `Zicsr` | `src/Zicsr/csr_decode.vhd` | `opcode = OPCODE_SYSTEM` (`"1110011"`) | `o_use_imm_i = '1'` para toda a classe `SYSTEM`; `o_is_csr = '1'` e `o_we_reg = '1'` quando `funct3` é diferente de `"000"` e `"100"` |
| `Zimop` | `src/Zimop/zimop_decode.vhd` | `opcode = OPCODE_SYSTEM`, `funct3 = "100"` e os campos fixos de `mop.r.n` e `mop.rr.n` (ver [Zimop](../ISA/Zimop/instructions.md)) | `o_we_reg = '1'`; a operação da ULA vira `ALU_BGEU` (resultado zero) e o `opcode` apresentado a EX vira `OPCODE_OP_IMM` |
| `Zihintntl` | `src/Zihintntl/zihintntl_decode.vhd` | `opcode = OPCODE_OP`, `funct7 = "0000000"`, `funct3 = "000"`, `rd` e `rs1` em `x0` e `rs2` de `x2` a `x5` (ver [Zihintntl](../ISA/Zihintntl/instructions.md)) | `o_is_hint = '1'`; o estágio ID desabilita a escrita em `rd` |
| `Zihintpause` | `src/Zihintpause/zihintpause_decode.vhd` | A palavra `0x0100000F` (ver [Zihintpause](../ISA/Zihintpause/instructions.md)) | `o_is_hint = '1'`; o estágio ID desabilita a escrita em `rd` |

O estágio ID combina as habilitações de escrita por disjunção lógica (`cu_we_reg <= base_we_reg or m_we_reg or csr_we_reg or zc_we_reg`) e propaga os indicadores `o_is_muldiv` e `o_is_csr` pelo registrador de barreira `reg_id_ex` até o estágio EX.

### 2.2. Efeitos Permitidos no Pipeline

Uma extensão interage com o controle global do pipeline em `src/core/core.vhd` exclusivamente por três mecanismos:

1. **Parada por ocupação multiciclo (`o_muldiv_stall` / `o_fencei_busy`):** congela os estágios anteriores enquanto a operação aguarda conclusão.
2. **Descarte e redirecionamento de fluxo (`o_fencei_take`, `o_mret_take`):** esvazia `reg_if_id` e `reg_id_ex` e redireciona o PC para `o_redirect_pc`.
3. **Exceção síncrona ou interrupção (`o_trap_take`):** além de esvaziar `reg_if_id` e `reg_id_ex` e redirecionar o PC para `mtvec`, aplica flush em `reg_ex_mem` para impedir que a instrução faltante altere registradores ou memória.

### 2.3. Caminho de Resultado e Forwarding

No estágio EX (`src/core/stage_ex.vhd`), o resultado produzido pela extensão (`ex_muldiv_result` quando `i_is_muldiv = '1'` ou `csr_rdata` quando `i_is_csr = '1'`) é multiplexado em `ex_alu_mux_result` junto com `ex_alu_result`. Dessa forma, o resultado atravessa `reg_ex_mem` e `reg_mem_wb` e é atendido pela malha de adiantamento (`forwarding_unit`) sem caminhos especiais no banco de registradores.

## 3. Especificação por Extensão

### 3.1. Extensão M (`src/M/multdiv.vhd`)

A unidade `multdiv` encapsula o multiplicador de Booth radix-2 (`booth_multiplier_rv32`), o divisor não-restaurador de 34 bits (`non_restoring_divider_rv32`) e a lógica de controle de partida e retenção:

| Porta de `multdiv` | Direção | Comportamento |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | `in` | Relógio principal e reset ativo em `'1'` |
| `i_valid`, `i_is_muldiv` | `in` | Indicam instrução válida da extensão M presente no estágio EX |
| `i_funct3` | `in` | Seleciona a operação (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`) e é registrado internamente no início do cálculo |
| `i_a`, `i_b` | `in` | Operandos `rs1` e `rs2` já resolvidos pelas multiplexações de forwarding |
| `o_result` | `out` | Resultado de 32 bits registrado na borda em que `o_done = '1'` |
| `o_busy` | `out` | Sobe combinacionalmente no próprio ciclo de partida (*eager stall*) e permanece em `'1'` durante os ciclos de iteração |
| `o_done` | `out` | Pulso de 1 ciclo ao término do cálculo |
| `o_stall` | `out` | Ativo enquanto `o_busy = '1'` ou `o_done = '1'`, mantendo o pipeline retido até a captura de `o_result` |
| `o_fused` | `out` | Pulso de 1 ciclo no término de uma operação fundida com a anterior (resultado do par vem do registro de `muldiv_fusion`, sem repetir o cálculo) |

### 3.2. Extensão Zicsr e Exceções (`src/Zicsr/csr_file.vhd` e `src/Zicsr/trap_unit.vhd`)

O perfil `rv32im_zicsr` habilita `HAS_ZICSR = true`. O banco de CSRs e a unidade de traps operam no estágio EX:

| Aspecto | Especificação |
| :--- | :--- |
| Leitura de CSR | Combinacional em `o_rdata`, retornando o valor anterior à escrita da instrução |
| Escrita em CSR | Efetivada na borda de subida quando `i_commit = i_is_csr and i_valid and i_pipe_run = '1'` sem exceção ativa; `CSRRW`/`CSRRWI` sempre escrevem, enquanto `CSRRS`/`CSRRC` e suas formas imediatas só escrevem se `i_src_zero = '0'` |
| Operando de escrita | `ex_fwd_rs1_val` para instruções por registrador (`i_funct3(2) = '0'`) ou o índice `i_rs1_idx` estendido com zero para 32 bits nas formas imediatas (`i_funct3(2) = '1'`) |
| Hazard load-use | A `hazard_detection_unit` inclui `OPCODE_SYSTEM` entre os leitores de `rs1`, inserindo 1 ciclo de stall quando precedido por um load para o mesmo registrador |
| Acesso ilegal | `csr_file` asserta `o_illegal = '1'` para endereços CSR não implementados ou tentativas de escrita efetiva em CSRs somente leitura (`i_addr[11:10] = "11"`) |
| `misa` | Lê RV32I, mais a extensão M (bit 12) quando `HAS_M = true`; a Zmmul não tem bit próprio; escritas são ignoradas |
| Interrupções | Com `HAS_INTERRUPTS = true`, `mip` espelha as portas `i_irq_software`, `i_irq_timer` e `i_irq_external`, `mie` guarda os bits 3, 7 e 11 e a `trap_unit` toma a interrupção de maior prioridade (externa, software, timer) sobre a instrução em EX quando `mstatus.MIE`, o bit de `mie` e o de `mip` valem `1` (ver [Zicsr](../ISA/Zicsr/description.md)); sem a constante, `mie` e `mip` leem zero e ignoram escritas |
| Não implementados | Os contadores `cycle`, `time` e `instret` existem só com `HAS_ZICNTR = true`, e sem ele o acesso é um acesso CSR ilegal |

Exceções síncronas detectadas por `trap_unit` (no máximo uma por instrução, com prioridade de cima para baixo). As causas 4 e 6 saem da instância do estágio MEM quando `HAS_ZICSR = true`, um ciclo depois das demais, e valem sobre a instrução que está em EX. A `control_unit` sinaliza um encoding indefinido no estágio ID, o `m_decode` retira o sinal das instruções M, e o sinal chega a EX pelo `reg_id_ex`. Sem `HAS_ZICSR` não há unidade de traps, e um encoding indefinido executa como `NOP`:

| Código (`o_cause`) | Exceção | Valor gravado em `mtval` (`o_tval`) |
| ---: | :--- | :--- |
| `0` | Endereço-alvo de branch ou salto tomado com bits `[1:0] /= "00"` | Endereço-alvo desalinhado (`i_cf_target`) |
| `2` | Instrução `SYSTEM` não suportada (`funct3 = "100"`, `SRET`, `SFENCE.VMA`, ou `ECALL`/`EBREAK`/`MRET`/`WFI` com `rd /= x0` ou `rs1 /= x0`), acesso CSR ilegal (`i_csr_illegal = '1'`) ou qualquer encoding que o RV32IM não define (`i_illegal = '1'`: opcode reservado, `funct3` ou `funct7` inválido, tudo zero, tudo um, encoding comprimido ou `FENCE.I` com `HAS_ZIFENCEI = false`) | `0x00000000` |
| `3` | Breakpoint (`EBREAK`, `imm12 = 0x001`) | `0x00000000` |
| `4` | Endereço efetivo de Load desalinhado que o hardware não executa: fora da memória principal (Memória de boot e FLASH direta), com as duas palavras em regiões diferentes (por exemplo, o fim da RAM e a faixa acima dela), ou qualquer load desalinhado com `HAS_ZICCLSM = false` | Endereço efetivo (`i_ea`) |
| `6` | Endereço efetivo de Store desalinhado que o hardware não executa, nas mesmas condições da causa 4 | Endereço efetivo (`i_ea`) |
| `11` | Chamada de ambiente do modo máquina (`ECALL`, `imm12 = 0x000`) | `0x00000000` |

Ao tomar uma interrupção (`o_take = '1'` e `o_irq = '1'`), `o_cause` traz o `mcause` da interrupção (bit 31 em `1`), `o_tval` vale zero, `mepc` recebe o PC da instrução em EX, que é abortada e refeita no retorno, e o PC salta para `mtvec` (ou para `BASE + 4 x causa`, no modo vetorado). A interrupção tem prioridade sobre qualquer exceção e sobre o `MRET`, e não aborta `FENCE.I`.

Ao tomar uma exceção (`o_take = '1'`), `mepc` recebe o PC da instrução, `mcause` recebe `o_cause`, `mtval` recebe `o_tval`, `mstatus.MPIE` recebe `mstatus.MIE`, `mstatus.MIE` é zerado e o PC salta para `mtvec`. Na instrução `MRET` (`0x30200073`), `mstatus.MIE` restaura `mstatus.MPIE`, `mstatus.MPIE` recebe `'1'` e o PC salta para `mepc`. A instrução `WFI` (`0x10500073`) executa como `NOP`.

Registradores CSR implementados no modo máquina:

| Endereço | Nome | Acesso | Valor de Reset | Máscara / Campos implementados |
| :--- | :--- | :--- | :--- | :--- |
| `0x300` | `mstatus` | Leitura e escrita | `0x00001800` | `MPP` (bits `[12:11]`) fixo em `"11"`; bits `MIE` (bit 3) e `MPIE` (bit 7) graváveis |
| `0x301` | `misa` | Somente leitura | `0x40001100` | RV32 (`MXL = 1`) com extensões `I` e `M`; com `IS_E` verdadeiro a base é a `E` e o valor é `0x40001010` |
| `0x304`, `0x344` | `mie`, `mip` | `mie` RW, `mip` RO | `0x00000000` | Com `HAS_INTERRUPTS`, bits 3, 7 e 11 (`mie` grava, `mip` espelha as linhas); os demais fixos em zero. Sem a constante, todos fixos em zero |
| `0x305` | `mtvec` | Leitura e escrita | `0x00000000` | `BASE` nos bits `[31:2]` e `MODE` no bit 0, que só grava com `HAS_INTERRUPTS` (vetorado); o bit 1 é fixo em `0`. No modo vetorado os bits `[5:2]` de `BASE` leem zero |
| `0x723` a `0x73F` | `mhpmevent3h` a `mhpmevent31h` | Leitura e escrita | `0x00000000` | Só com `HAS_SSCOFPMF`: `OF` (bit 31) e `MINH` (bit 30) do contador de mesmo índice; sem a constante o endereço é inexistente. O bit 13 de `mie` e de `mip` é `LCOFIE` e `LCOFIP` ([Sscofpmf](../ISA/Sscofpmf/description.md)) |
| `0x310` | `mstatush` | Leitura e escrita | `0x00000000` | Todos os bits fixos em zero |
| `0x340`, `0x342`, `0x343` | `mscratch`, `mcause`, `mtval` | Leitura e escrita | `0x00000000` | 32 bits completos |
| `0x341` | `mepc` | Leitura e escrita | `0x00000000` | Bits `[1:0]` fixos em `"00"` |
| `0xF11`..`0xF15` | `mvendorid`, `marchid`, `mimpid`, `mhartid`, `mconfigptr` | Somente leitura | `0x00000000` | Lidos constantemente como zero |

### 3.3. Extensão Zifencei (`src/Zifencei/fencei_unit.vhd`)

O perfil `rv32im_zicsr_zifencei` habilita `HAS_ZIFENCEI = true`:

| Aspecto | Comportamento |
| :--- | :--- |
| Busca de instruções em região atendida pelo barramento (FLASH com `FLASH_ON_BUS`, RAM com `RAM_ON_BUS` ou fora das três regiões) | O estágio IF asserta `o_ic_sel = '1'` e lê `i_ic_data`. Enquanto `i_ic_ready = '0'`, o PC permanece congelado e `o_instr_valid = '0'` injeta bolhas em `reg_if_id`, enquanto EX, MEM e WB continuam avançando |
| Execução de `FENCE.I` sem D-cache (`HAS_DCACHE = false`) | Quando `FENCE.I` está válida em EX e `i_base_run = '1'`, `o_take` pulsa por 1 ciclo, acionando `o_ic_inval = '1'`, limpando `IF/ID` e `ID/EX` e redirecionando o PC para $\text{PC} + 4$ |
| Execução de `FENCE.I` com D-cache write-back (`HAS_DCACHE = true`) | A unidade retém a instrução em EX por um ciclo, para que os stores anteriores deixem MEM e cheguem à cache, emite um pulso em `o_dc_flush` (`o_flush_req`) e mantém `o_busy = '1'` (congelando PC, `IF/ID` e `ID/EX` e injetando bolhas em `EX/MEM`) até receber `i_dc_done = '1'`, que a cache pode levantar no próprio ciclo do pulso em `o_dc_flush` ou em qualquer ciclo depois, momento em que pulsa `o_take = '1'` e invalida a I-cache |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
