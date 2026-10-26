# 1. Contrato de Extensão do Pipeline RV32

## 1. Escopo do Contrato

A especificação RISC-V define a semântica arquitetural de cada instrução (opcodes, campos `funct3`/`funct7` e efeito nos registradores). O contrato de extensão define como o hardware de uma extensão (`M/`, `Zicsr/`, `Zifencei/`) se conecta aos estágios do pipeline (`core/`) sem acoplar a lógica base (`common/` e `I/`) aos detalhes internos de cada extensão.

Cada extensão reside em sua própria pasta e é habilitada no topo `core/core.vhd` por um generic booleano (`has_m`, `has_zicsr`, `has_zifencei`, `has_dcache`). Quando o generic correspondente vale `false`, as instruções daquela extensão comportam-se como `NOP` (sem escrita em registrador, sem acesso à memória e sem parada do pipeline).

## 2. Regras de Integração no Pipeline

### 2.1. Decodificação no Estágio ID

A unidade de controle base (`common/control_unit.vhd`) decodifica exclusivamente o conjunto RV32I. Instruções de extensões opcionais são reivindicadas por decodificadores dedicados instanciados condicionalmente em `core/stage_id.vhd`:

| Extensão | Decodificador em `stage_id` | Condição de reivindicação | Sinais ativados |
| :--- | :--- | :--- | :--- |
| `M` | `M/m_decode.vhd` | `opcode = OPCODE_OP` (`"0110011"`) e `funct7 = FUNCT7_MULDIV` (`"0000001"`) | `o_is_muldiv = '1'`, `o_we_reg = '1'`, `o_sel_pc_rs1 = '1'` |
| `Zicsr` | `Zicsr/csr_decode.vhd` | `opcode = OPCODE_SYSTEM` (`"1110011"`) | `o_use_imm_i = '1'` para toda a classe `SYSTEM`; `o_is_csr = '1'` e `o_we_reg = '1'` quando `funct3` é diferente de `"000"` e `"100"` |

O estágio ID combina as habilitações de escrita por disjunção lógica (`cu_we_reg <= base_we_reg or m_we_reg or csr_we_reg`) e propaga os indicadores `o_is_muldiv` e `o_is_csr` pelo registrador de barreira `reg_id_ex` até o estágio EX.

### 2.2. Efeitos Permitidos no Pipeline

Uma extensão interage com o controle global do pipeline em `core/core.vhd` exclusivamente por três mecanismos:

1. **Parada por ocupação multiciclo (`o_muldiv_stall` / `o_fencei_busy`):** congela os estágios anteriores enquanto a operação aguarda conclusão.
2. **Descarte e redirecionamento de fluxo (`o_fencei_take`, `o_mret_take`):** esvazia `reg_if_id` e `reg_id_ex` e redireciona o PC para `o_redirect_pc`.
3. **Exceção síncrona (`o_trap_take`):** além de esvaziar `reg_if_id` e `reg_id_ex` e redirecionar o PC para `mtvec`, aplica flush em `reg_ex_mem` para impedir que a instrução faltante altere registradores ou memória.

### 2.3. Caminho de Resultado e Forwarding

No estágio EX (`core/stage_ex.vhd`), o resultado produzido pela extensão (`ex_muldiv_result` quando `i_is_muldiv = '1'` ou `csr_rdata` quando `i_is_csr = '1'`) é multiplexado em `ex_alu_mux_result` junto com `ex_alu_result`. Dessa forma, o resultado atravessa `reg_ex_mem` e `reg_mem_wb` e é atendido pela malha de adiantamento (`forwarding_unit`) sem caminhos especiais no banco de registradores.

## 3. Especificação por Extensão

### 3.1. Extensão M (`M/multdiv.vhd`)

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

### 3.2. Extensão Zicsr e Exceções (`Zicsr/csr_file.vhd` e `Zicsr/trap_unit.vhd`)

O perfil `rv32im_zicsr` habilita `has_zicsr = true`. O banco de CSRs e a unidade de traps operam no estágio EX:

| Aspecto | Especificação |
| :--- | :--- |
| Leitura de CSR | Combinacional em `o_rdata`, retornando o valor anterior à escrita da instrução |
| Escrita em CSR | Efetivada na borda de subida quando `i_commit = i_is_csr and i_valid and i_pipe_run = '1'` sem exceção ativa; `CSRRW`/`CSRRWI` sempre escrevem, enquanto `CSRRS`/`CSRRC` e suas formas imediatas só escrevem se `i_src_zero = '0'` |
| Operando de escrita | `ex_fwd_rs1_val` para instruções por registrador (`i_funct3(2) = '0'`) ou o índice `i_rs1_idx` estendido com zero para 32 bits nas formas imediatas (`i_funct3(2) = '1'`) |
| Hazard load-use | A `hazard_detection_unit` inclui `OPCODE_SYSTEM` entre os leitores de `rs1`, inserindo 1 ciclo de stall quando precedido por um load para o mesmo registrador |
| Acesso ilegal | `csr_file` asserta `o_illegal = '1'` para endereços CSR não implementados ou tentativas de escrita efetiva em CSRs somente leitura (`i_addr[11:10] = "11"`) |
| `misa` | Lê RV32I, mais a extensão M (bit 12) quando `has_m = true`; escritas são ignoradas |
| Não implementados | `cycle`, `time` e `instret` (o acesso é um acesso CSR ilegal) e interrupções (`mie` e `mip` leem zero e ignoram escritas) |

Exceções síncronas detectadas por `trap_unit` (no máximo uma por instrução, com prioridade de cima para baixo). A `control_unit` sinaliza um encoding indefinido no estágio ID, o `m_decode` retira o sinal das instruções M, e o sinal chega a EX pelo `reg_id_ex`. Sem `has_zicsr` não há unidade de traps, e um encoding indefinido executa como `NOP`:

| Código (`o_cause`) | Exceção | Valor gravado em `mtval` (`o_tval`) |
| ---: | :--- | :--- |
| `0` | Endereço-alvo de branch ou salto tomado com bits `[1:0] /= "00"` | Endereço-alvo desalinhado (`i_cf_target`) |
| `2` | Instrução `SYSTEM` não suportada (`funct3 = "100"`, `SRET`, `SFENCE.VMA`, ou `ECALL`/`EBREAK`/`MRET`/`WFI` com `rd /= x0` ou `rs1 /= x0`), acesso CSR ilegal (`i_csr_illegal = '1'`) ou qualquer encoding que o RV32IM não define (`i_illegal = '1'`: opcode reservado, `funct3` ou `funct7` inválido, tudo zero, tudo um, encoding comprimido ou `FENCE.I` com `has_zifencei = false`) | `0x00000000` |
| `3` | Breakpoint (`EBREAK`, `imm12 = 0x001`) | `0x00000000` |
| `4` | Endereço efetivo de Load desalinhado (`LW` com `ea[1:0] /= "00"`, `LH`/`LHU` com `ea[0] = '1'`) | Endereço efetivo (`i_ea`) |
| `6` | Endereço efetivo de Store desalinhado (`SW` com `ea[1:0] /= "00"`, `SH` com `ea[0] = '1'`) | Endereço efetivo (`i_ea`) |
| `11` | Chamada de ambiente do modo máquina (`ECALL`, `imm12 = 0x000`) | `0x00000000` |

Ao tomar uma exceção (`o_take = '1'`), `mepc` recebe o PC da instrução, `mcause` recebe `o_cause`, `mtval` recebe `o_tval`, `mstatus.MPIE` recebe `mstatus.MIE`, `mstatus.MIE` é zerado e o PC salta para `mtvec`. Na instrução `MRET` (`0x30200073`), `mstatus.MIE` restaura `mstatus.MPIE`, `mstatus.MPIE` recebe `'1'` e o PC salta para `mepc`. A instrução `WFI` (`0x10500073`) executa como `NOP`.

Registradores CSR implementados no modo máquina:

| Endereço | Nome | Acesso | Valor de Reset | Máscara / Campos implementados |
| :--- | :--- | :--- | :--- | :--- |
| `0x300` | `mstatus` | Leitura e escrita | `0x00001800` | `MPP` (bits `[12:11]`) fixo em `"11"`; bits `MIE` (bit 3) e `MPIE` (bit 7) graváveis |
| `0x301` | `misa` | Somente leitura | `0x40001100` | RV32 (`MXL = 1`) com extensões `I` e `M` |
| `0x304`, `0x344` | `mie`, `mip` | `mie` RW, `mip` RO | `0x00000000` | Todos os bits fixos em zero |
| `0x305` | `mtvec` | Leitura e escrita | `0x00000000` | Bits `[1:0]` fixos em `"00"` (modo direto) |
| `0x310` | `mstatush` | Leitura e escrita | `0x00000000` | Todos os bits fixos em zero |
| `0x340`, `0x342`, `0x343` | `mscratch`, `mcause`, `mtval` | Leitura e escrita | `0x00000000` | 32 bits completos |
| `0x341` | `mepc` | Leitura e escrita | `0x00000000` | Bits `[1:0]` fixos em `"00"` |
| `0xF11`..`0xF15` | `mvendorid`, `marchid`, `mimpid`, `mhartid`, `mconfigptr` | Somente leitura | `0x00000000` | Lidos constantemente como zero |

### 3.3. Extensão Zifencei (`Zifencei/fencei_unit.vhd`)

O perfil `rv32im_zicsr_zifencei` habilita `has_zifencei = true`:

| Aspecto | Comportamento |
| :--- | :--- |
| Busca de instruções em SDRAM (`>= 0x40000000`) | O estágio IF asserta `o_ic_sel = '1'` e lê `i_ic_data`. Enquanto `i_ic_ready = '0'`, o PC permanece congelado e `o_instr_valid = '0'` injeta bolhas em `reg_if_id`, enquanto EX, MEM e WB continuam avançando |
| Execução de `FENCE.I` sem D-cache (`has_dcache = false`) | Quando `FENCE.I` está válida em EX e `i_base_run = '1'`, `o_take` pulsa por 1 ciclo, acionando `o_ic_inval = '1'`, limpando `IF/ID` e `ID/EX` e redirecionando o PC para $\text{PC} + 4$ |
| Execução de `FENCE.I` com D-cache write-back (`has_dcache = true`) | A unidade emite um pulso em `o_dc_flush` (`o_flush_req`) e mantém `o_busy = '1'` (congelando PC, `IF/ID` e `ID/EX` e injetando bolhas em `EX/MEM`) até receber `i_dc_done = '1'`, que deve vir pelo menos um ciclo depois do pulso em `o_dc_flush` porque a unidade só o aceita depois disso, momento em que pulsa `o_take = '1'` e invalida a I-cache |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
