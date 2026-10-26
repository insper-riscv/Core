# Guia de Estágios e Sinais do Pipeline RV32

Este guia detalha as entradas, saídas, componentes internos e códigos de controle de cada um dos cinco estágios e quatro registradores de barreira do processador.

## 1. Topo Estrutural e Estágios do Pipeline

O processador é dividido em cinco entidades de estágio localizadas em `core/` e quatro registradores de barreira em `common/`, interconectados pelo topo `core/core.vhd`:

| Ordem | Entidade | Arquivo | Função principal |
| :--- | :--- | :--- | :--- |
| 1 | `stage_if` | `core/stage_if.vhd` | Seleção de fonte do próximo PC, incremento $\text{PC} + 4$, decodificação de região de código (Boot ROM, Flash, I-cache SDRAM) e controle de espera de busca |
| Barreira 1 | `reg_if_id` | `common/reg_if_id.vhd` | Registro síncrono de `o_valid`, `o_pc`, `o_pc4` e `o_inst` entre IF e ID |
| 2 | `stage_id` | `core/stage_id.vhd` | Decodificação RV32I + extensões `M`/`Zicsr`, extensão de imediato, leitura/escrita do banco de registradores, detecção de hazard load-use e inserção de bolha |
| Barreira 2 | `reg_id_ex` | `common/reg_id_ex.vhd` | Registro síncrono de operandos, imediato, índices de registradores e sinais de controle entre ID e EX |
| 3 | `stage_ex` | `core/stage_ex.vhd` | Forwarding de operandos, execução na ULA, unidade MulDiv, banco de CSRs e Trap Unit, unidade `FENCE.I`, cálculo de desvios e alinhamento de store |
| Barreira 3 | `reg_ex_mem` | `common/reg_ex_mem.vhd` | Registro síncrono do resultado de EX, dados e máscara de bytes de store, destino `rd` e controles de memória/WB entre EX e MEM |
| 4 | `stage_mem` | `core/stage_mem.vhd` | Decodificação do espaço de dados (Flash porta 2, RAM interna e janela externa SDRAM/periféricos) e controle de espera `o_sdram_wait` |
| Barreira 4 | `reg_mem_wb` | `common/reg_mem_wb.vhd` | Registro síncrono de `o_pc4`, `o_alu_out`, `o_rd`, `o_we_reg`, `o_ext_ram_op` e `o_wb_sel` entre MEM e WB |
| 5 | `stage_wb` | `core/stage_wb.vhd` | Seleção da palavra lida da memória, extensão de byte/meia-palavra (`extender_ram`) e seleção do valor final de escrita no banco de registradores |

## 2. Detalhamento por Estágio

### 2.1. Estágio 1: Busca de Instrução (`stage_if` e `pc_fetch`)

O estágio IF seleciona o próximo endereço de instrução por meio do código `pc_src` (`pc_src_t`) definido em `common/pc_src_consts.vhd`:

| Constante | Código | Fonte selecionada no `mux_4x1` de `pc_fetch` |
| :--- | :--- | :--- |
| `PC_SRC_PC4` | `"00"` | $\text{PC} + 4$ calculado pelo somador `u_pc4_adder` |
| `PC_SRC_BRANCH` | `"01"` | `i_branch_target` ($\text{PC} + \text{imm}$, para `BRANCH` tomado ou `JAL`) |
| `PC_SRC_JALR` | `"10"` | `i_jalr_target` ($((\text{rs1} + \text{imm}) \land \texttt{0xFFFFFFFE})$, para `JALR`) |
| `PC_SRC_REDIRECT` | `"11"` | `i_redirect_pc` (`mepc` em `MRET`, $\text{PC} + 4$ em `FENCE.I` ou `mtvec` em exceção) |

A decodificação do endereço de busca (`if_pc`) utiliza os limites de `common/mem_map_consts.vhd`:

| Faixa de endereço (`if_pc`) | Região selecionada | Palavra entregue em `o_instr` |
| :--- | :--- | :--- |
| `< 0x00000800` (`BOOT_ROM_SIZE_BYTES`) | Boot ROM | `i_boot_rom_data` |
| `0x00000800 .. 0x3FFFFFFF` | Memória Flash (porta 1) | `i_flash_data` |
| `>= 0x40000000` (`SDRAM_BASE_BYTES`) | Cache de instruções externa (SDRAM, `o_ic_sel = '1'`) | `i_ic_data` (congela o PC e anula `o_instr_valid` enquanto `i_ic_ready = '0'`) |

### 2.2. Estágio 2: Decodificação e Leitura de Registradores (`stage_id`)

O estágio ID reúne seis subblocos:

1. **Unidade de controle base (`control_unit`):** decodifica `i_inst` gerando `o_sel_pc4_alu`, `o_ext_imm_op`, `o_wb_sel`, `o_we_reg`, `o_ext_ram_op`, `o_sel_rs2_imm`, `o_sel_pc_rs1`, `o_alu_op`, `o_we_ram`, `o_re_ram`, `o_en_ram`, `o_opcode` e `o_funct3`.
2. **Decodificador RV32M (`m_decode`, quando `has_m = true`):** ativa `o_is_muldiv = '1'`, `o_we_reg = '1'` e `o_sel_pc_rs1 = '1'` quando `opcode = OPCODE_OP` e `funct7 = FUNCT7_MULDIV`.
3. **Decodificador Zicsr (`csr_decode`, quando `has_zicsr = true`):** ativa `o_use_imm_i = '1'` para toda a classe `OPCODE_SYSTEM` e ativa `o_is_csr = '1'` e `o_we_reg = '1'` quando `funct3` é diferente de `"000"` e `"100"`.
4. **Extensor de imediatos (`extender_imm`):** reconstrói o imediato de 32 bits de acordo com `common/ext_imm_consts.vhd`:

| Constante | Código | Formato e operação de extensão |
| :--- | :--- | :--- |
| `EXT_IMM_U` | `"000"` | $\text{instr}[31{:}12] \ll 12$ (`LUI`, `AUIPC`) |
| `EXT_IMM_I` | `"001"` | $\text{sext}(\text{instr}[31{:}20])$ (I-type aritmético, loads, `JALR`, endereço CSR) |
| `EXT_IMM_I_SHAMT` | `"010"` | $\text{zext}(\text{instr}[24{:}20])$ (`SLLI`, `SRLI`, `SRAI`) |
| `EXT_IMM_J` | `"011"` | $\text{sext}(\text{instr}[31] \,\&\, \text{instr}[19{:}12] \,\&\, \text{instr}[20] \,\&\, \text{instr}[30{:}21] \,\&\, \texttt{'0'})$ (`JAL`) |
| `EXT_IMM_S` | `"100"` | $\text{sext}(\text{instr}[31{:}25] \,\&\, \text{instr}[11{:}7])$ (`SB`, `SH`, `SW`) |
| `EXT_IMM_B` | `"101"` | $\text{sext}(\text{instr}[31] \,\&\, \text{instr}[7] \,\&\, \text{instr}[30{:}25] \,\&\, \text{instr}[11{:}8] \,\&\, \texttt{'0'})$ (`BEQ`..`BGEU`) |

5. **Banco de registradores (`reg_file`):** 32 registradores de 32 bits (`x0` fixo em zero e `x1`..`x31` instanciados com `generic_register`), decodificação de escrita via `onehot_decoder`, leitura combinacional dupla via `mux_tree` e bypass write-through via `mux_2x1` quando `i_enable = '1'` e o endereço lido coincide com `i_rd /= x0`.
6. **Detecção de hazards (`hazard_detection_unit`) e inserção de bolha (`bubble_mux`):** congela PC e IF/ID (`o_pc_we = '0'`, `o_ifid_we = '0'`) e zera `o_we_reg`, `o_we_ram`, `o_re_ram` e `o_en_ram` (`o_bubble_sel = '1'`) durante conflitos load-use ou stalls multiciclo (`i_pipe_stall = '1'`).

### 2.3. Estágio 3: Execução (`stage_ex`)

No estágio EX:

1. **Adiantamento (`forwarding_unit`):** seleciona cada operando (`ex_fwd_rs1_val` e `ex_fwd_rs2_val`) via `mux_4x1` entre o valor vindo de ID/EX (`"00"`), o dado final de WB (`"01"`) e o resultado em EX/MEM (`"10"`).
2. **Seleção de entrada da ULA:** dois multiplexadores `mux_2x1` escolhem o operando A (`i_pc` quando `i_sel_pc_rs1 = '0'`, ou `ex_fwd_rs1_val` quando `'1'`) e o operando B (`ex_fwd_rs2_val` quando `i_sel_rs2_imm = '0'`, ou `i_imm` quando `'1'`).
3. **ULA (`alu`):** executa a operação definida em `common/alu_consts.vhd`:

| Constante | Código | Operação em `o_d` | Flag `o_branch` |
| :--- | :--- | :--- | :--- |
| `ALU_PASS_B` | `"00000"` | `i_b` | `'0'` |
| `ALU_ADD` | `"00001"` | `unsigned(i_a) + unsigned(i_b)` | `'0'` |
| `ALU_XOR` | `"00010"` | `i_a xor i_b` | `'0'` |
| `ALU_OR` | `"00011"` | `i_a or i_b` | `'0'` |
| `ALU_AND` | `"00100"` | `i_a and i_b` | `'0'` |
| `ALU_SLL` | `"00101"` | `i_a << unsigned(i_b[4:0])` | `'0'` |
| `ALU_SRL` | `"00110"` | `unsigned(i_a) >> unsigned(i_b[4:0])` | `'0'` |
| `ALU_SRA` | `"00111"` | `signed(i_a) >> unsigned(i_b[4:0])` | `'0'` |
| `ALU_SUB` | `"01000"` | `unsigned(i_a) - unsigned(i_b)` | `'0'` |
| `ALU_SLT` | `"01001"` | `1` se `signed(i_a) < signed(i_b)`, senão `0` | `'0'` |
| `ALU_SLTU` | `"01010"` | `1` se `unsigned(i_a) < unsigned(i_b)`, senão `0` | `'0'` |
| `ALU_BEQ` | `"01011"` | `0` | `'1'` se `i_a = i_b` |
| `ALU_BNE` | `"01100"` | `0` | `'1'` se `i_a /= i_b` |
| `ALU_BLT` | `"01101"` | `0` | `'1'` se `signed(i_a) < signed(i_b)` |
| `ALU_BGE` | `"01110"` | `0` | `'1'` se `signed(i_a) >= signed(i_b)` |
| `ALU_BLTU` | `"01111"` | `0` | `'1'` se `unsigned(i_a) < unsigned(i_b)` |
| `ALU_BGEU` | `"10000"` | `0` | `'1'` se `unsigned(i_a) >= unsigned(i_b)` |
| `ALU_JALR` | `"10001"` | `(unsigned(i_a) + unsigned(i_b)) & ~1` | `'0'` |

4. **Seleção do resultado de EX:** o sinal `ex_alu_mux_result` escolhe entre `ex_muldiv_result` (`i_is_muldiv = '1'`), `csr_rdata` (`i_is_csr = '1'`) e `ex_alu_result`. Em seguida, `u_mux_ex_final` (`mux_2x1`) seleciona entre `ex_alu_mux_result` (`i_sel_pc4_alu = '0'`) e `i_pc4` (`i_sel_pc4_alu = '1'`, usado em `JAL` e `JALR`).
5. **Alinhamento de Store (`store_manager`):** desloca `ex_fwd_rs2_val` para as lanes de byte correspondentes a `ex_alu_result(1 downto 0)` e gera a máscara de 4 bits `o_store_byte_mask` (`"1111"` para `SW`, `"0011"`/`"1100"` para `SH` e `"0001"`/`"0010"`/`"0100"`/`"1000"` para `SB`).

### 2.4. Estágio 4: Acesso à Memória de Dados (`stage_mem`)

O estágio MEM decodifica o endereço efetivo `i_alu_out` conforme os limites de `common/mem_map_consts.vhd`:

| Faixa de endereço (`i_alu_out`) | Subsistema de memória acionado | Sinais ativos |
| :--- | :--- | :--- |
| `< 0x00008000` (`RAM_BASE_BYTES`) | Memória Flash (porta 2, somente leitura) | `o_flash_addr2`, `o_flash_rden2 = i_re_ram and i_valid` |
| `0x00008000 .. 0x3FFFFFFF` | Memória RAM interna (1 ciclo de latência) | `o_ram_addr`, `o_ram_wdata`, `o_ram_byteena`, `o_ram_en`, `o_ram_wren`, `o_ram_rden` |
| `>= 0x40000000` (`SDRAM_BASE_BYTES`) | Barramento externo SDRAM e periféricos | `o_sdram_addr`, `o_sdram_wdata`, `o_sdram_byteena`, `o_sdram_rden`, `o_sdram_wren`, `o_sdram_wait = sdram_access and (not i_sdram_ready)` |

### 2.5. Estágio 5: Write-Back (`stage_wb`)

No estágio WB, a palavra lida no ciclo anterior é selecionada entre `i_flash_data2`, `i_sdram_rdata` e `i_ram_rdata` a partir do endereço `i_alu_out`. O módulo `extender_ram` extrai o byte ou meia-palavra segundo `i_alu_out(1 downto 0)` e aplica o modo de extensão definido em `common/ext_ram_consts.vhd`:

| Constante | Código (`i_ext_ram_op`) | Operação de alinhamento e extensão |
| :--- | :--- | :--- |
| `EXT_RAM_LW` | `"000"` | Palavra completa de 32 bits (`i_data`) |
| `EXT_RAM_LH` | `"001"` | Meia-palavra selecionada por `i_byte_offset(1)` com extensão de sinal |
| `EXT_RAM_LHU` | `"010"` | Meia-palavra selecionada por `i_byte_offset(1)` com extensão por zero |
| `EXT_RAM_LB` | `"011"` | Byte selecionado por `i_byte_offset(1 downto 0)` com extensão de sinal |
| `EXT_RAM_LBU` | `"100"` | Byte selecionado por `i_byte_offset(1 downto 0)` com extensão por zero |

Por fim, o multiplexador `u_mux_wb` (`mux_4x1`) seleciona `o_wb_data` de acordo com `common/wb_sel_consts.vhd`:

| Constante | Código (`i_wb_sel`) | Dado selecionado para escrita no banco de registradores |
| :--- | :--- | :--- |
| `WB_SEL_ALU` | `"00"` | `i_alu_out` (resultado da ULA, da unidade MulDiv ou leitura de CSR) |
| `WB_SEL_PC4` | `"01"` | `i_pc4` (endereço de retorno de `JAL` e `JALR`) |
| `WB_SEL_RAM` | `"10"` | `wb_ram_extended` (dado de load formatado pelo `extender_ram`) |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../LICENSE).
