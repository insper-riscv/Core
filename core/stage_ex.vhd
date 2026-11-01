-- =============================================================================
-- Estágio EX (Execute) do Pipeline RV32
--
-- Conecta estruturalmente as unidades funcionais de execução, adiantamento de
-- dados (forwarding), cálculo de desvios, gerenciador de escritas em memória e
-- unidades de extensão do estágio EX:
--   1. Unidade de adiantamento (forwarding_unit) e muxes de operandos rs1/rs2.
--   2. ULA principal (alu) e somadores de endereço-alvo de branch/JAL e JALR.
--   3. Unidade de multiplicação e divisão inteira (multdiv, quando has_m = true; só a multiplicação quando has_zmmul = true).
--   4. Banco de CSRs e detector de exceções (csr_file e trap_unit, quando has_zicsr = true).
--   5. Unidade de sincronização FENCE.I (fencei_unit, quando has_zifencei = true).
--   6. Gerenciador de alinhamento de escrita em memória (store_manager).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;

entity stage_ex is
	generic (
		-- Habilita a unidade de multiplicação e divisão (multdiv) completa.
		has_m        : boolean := false;
		-- Habilita a multiplicação sem o divisor (extensão Zmmul); has_m já a inclui.
		has_zmmul    : boolean := false;
		-- Habilita o banco de registradores CSR e a unidade de traps (csr_file, trap_unit).
		has_zicsr    : boolean := false;
		-- Habilita os contadores da extensão Zicntr no banco de CSRs; exige has_zicsr.
		has_zicntr   : boolean := false;
		-- Ciclos de clock do core por tick do contador time.
		tick_cycles  : positive := 50;
		-- Habilita a unidade de sincronização de cache de instruções (fencei_unit).
		has_zifencei : boolean := false;
		-- Executa em hardware o acesso desalinhado à memória principal (extensão Zicclsm).
		has_zicclsm  : boolean := true;
		-- Habilita o handshake de flush com a cache de dados write-back em FENCE.I.
		has_dcache   : boolean := false;
		-- Quantidade de contadores de eventos da extensão Zihpm no banco de CSRs (0 = sem Zihpm); exige has_zicsr.
		hpm_counters : natural range 0 to 4 := 0
	);
	port (
		-- Vetor de eventos do SoC: o bit K vale '1' nos ciclos do evento de código K (contadores do Zihpm).
		i_hpm_events      : in  std_logic_vector(15 downto 0) := (others => '0');
		-- Sinal de clock principal do processador.
		i_clk             : in  std_logic;
		-- Sinal de reset ativo em '1'.
		i_rst             : in  std_logic;
		-- Indica que os estágios EX e MEM estão livres de stalls de memória/multdiv.
		i_base_run        : in  std_logic;
		-- Indica que os estágios anteriores a MEM estão avançando neste ciclo.
		i_pipe_run        : in  std_logic;
		-- Bit de validade da instrução no estágio EX.
		i_valid           : in  std_logic;
		-- Pulso de um ciclo: uma instrução foi retirada em EX (incrementa minstret com Zicntr).
		i_retire          : in  std_logic := '0';
		-- Endereço PC da instrução no estágio EX.
		i_pc              : in  word_t;
		-- Valor PC + 4 da instrução no estágio EX.
		i_pc4             : in  word_t;
		-- Índice do registrador fonte rs1 no estágio EX.
		i_rs1_idx         : in  reg_t;
		-- Índice do registrador fonte rs2 no estágio EX.
		i_rs2_idx         : in  reg_t;
		-- Índice do registrador destino rd no estágio EX.
		i_rd_idx          : in  reg_t;
		-- Valor original de rs1 vindo do registrador ID/EX.
		i_rs1_val         : in  word_t;
		-- Valor original de rs2 vindo do registrador ID/EX.
		i_rs2_val         : in  word_t;
		-- Imediato estendido de 32 bits vindo do registrador ID/EX.
		i_imm             : in  word_t;
		-- Seletor entre resultado de execução ('0') e PC + 4 ('1').
		i_sel_pc4_alu     : in  std_logic;
		-- Seletor entre rs2 ('0') e imediato ('1') para o operando B da ULA.
		i_sel_rs2_imm     : in  std_logic;
		-- Seletor entre PC ('0') e rs1 ('1') para o operando A da ULA.
		i_sel_pc_rs1      : in  std_logic;
		-- Código de operação da ULA.
		i_alu_op          : in  alu_op_t;
		-- Seleção one-hot do resultado da ULA vinda do registrador ID/EX.
		i_alu_sel         : in  alu_sel_t;
		-- Indica que a instrução em EX pertence à extensão M (decodificado no ID).
		i_is_muldiv       : in  std_logic;
		-- Indica que a instrução em EX pertence à extensão Zicsr (decodificado no ID).
		i_is_csr          : in  std_logic;
		-- Indica instrução inexistente em EX ('1' = ilegal; só gera exceção com has_zicsr).
		i_illegal         : in  std_logic;
		-- Campo opcode da instrução no estágio EX.
		i_opcode          : in  opcode_t;
		-- Campo funct3 da instrução no estágio EX.
		i_funct3          : in  funct3_t;
		-- Índice do registrador destino rd no estágio EX/MEM (para forwarding).
		i_exmem_rd        : in  reg_t;
		-- Habilitação de escrita em registrador no estágio EX/MEM.
		i_exmem_we_reg    : in  std_logic;
		-- Bit de validade da instrução no estágio EX/MEM.
		i_exmem_valid     : in  std_logic;
		-- Valor calculado no estágio EX/MEM para adiantamento (forwarding).
		i_exmem_alu_out   : in  word_t;
		-- Índice do registrador destino rd no estágio MEM/WB (para forwarding).
		i_memwb_rd        : in  reg_t;
		-- Habilitação de escrita em registrador no estágio MEM/WB.
		i_memwb_we_reg    : in  std_logic;
		-- Bit de validade da instrução no estágio MEM/WB.
		i_memwb_valid     : in  std_logic;
		-- Resultado do estágio EX da instrução em MEM/WB (registrado), para adiantamento. Um load nunca é adiantado daqui.
		i_memwb_alu_out   : in  word_t;
		-- Índice do registrador destino rd da instrução no registrador WB2 (para forwarding).
		i_wb2_rd          : in  reg_t;
		-- Habilitação de escrita em registrador da instrução no registrador WB2.
		i_wb2_we_reg      : in  std_logic;
		-- Dado final do estágio WB já registrado (WB2), para adiantamento (forwarding).
		i_wb2_data        : in  word_t;
		-- Confirmação de término do flush da cache de dados write-back (Zifencei).
		i_dc_done         : in  std_logic;
		-- Exceção de endereço do acesso à memória do estágio MEM: tem prioridade sobre a deste estágio.
		i_mem_trap_take   : in  std_logic := '0';
		-- Código mcause da exceção do estágio MEM.
		i_mem_trap_cause  : in  word_t    := (others => '0');
		-- PC da instrução em MEM que gerou a exceção (vira o mepc).
		i_mem_trap_pc     : in  word_t    := (others => '0');
		-- Valor de mtval da exceção do estágio MEM.
		i_mem_trap_tval   : in  word_t    := (others => '0');
		-- Resultado final de 32 bits do estágio EX (enviado ao registrador EX/MEM).
		o_final_result    : out word_t;
		-- Dado alinhado para escrita em memória (enviado ao registrador EX/MEM).
		o_store_data      : out word_t;
		-- Máscara de habilitação de bytes para escrita em memória (enviada ao EX/MEM).
		o_store_byte_mask : out byte_mask_t;
		-- Indica desvio condicional tomado ou salto JAL no estágio EX.
		o_branch_taken    : out std_logic;
		-- Indica salto indireto JALR tomado no estágio EX.
		o_jalr_taken      : out std_logic;
		-- Endereço alvo calculado para desvio condicional ou JAL.
		o_branch_target   : out word_t;
		-- Endereço alvo calculado e alinhado para salto JALR.
		o_jalr_target     : out word_t;
		-- Endereço de redirecionamento prioritário (mepc, PC + 4 pós-FENCE.I ou mtvec).
		o_redirect_pc     : out word_t;
		-- Pulso que indica tomada de exceção síncrona no estágio EX.
		o_trap_take       : out std_logic;
		-- Pulso que sinaliza uma exceção detectada em EX sem Zicsr (o core não tem CSRs para registrá-la).
		o_trap_sig        : out std_logic;
		-- Código de causa da exceção sinalizada, no formato do mcause (zero com Zicsr).
		o_trap_sig_cause  : out word_t;
		-- PC da instrução que gerou a exceção sinalizada (zero com Zicsr).
		o_trap_sig_pc     : out word_t;
		-- Pulso que indica execução de retorno de exceção (MRET) no estágio EX.
		o_mret_take       : out std_logic;
		-- Pulso que indica conclusão de instrução FENCE.I no estágio EX.
		o_fencei_take     : out std_logic;
		-- Indica que a instrução FENCE.I em EX aguarda término do flush da D-cache.
		o_fencei_busy     : out std_logic;
		-- Pulso de requisição de flush enviado à cache de dados write-back.
		o_dc_flush        : out std_logic;
		-- Indica que a unidade multdiv está ocupada ou concluindo captura de resultado.
		o_muldiv_stall    : out std_logic
	);
end entity stage_ex;

architecture rtl of stage_ex is

	-- Habilitações efetivas de forwarding dos estágios EX/MEM e MEM/WB.
	signal exmem_we_reg_fwd   : std_logic;
	-- Habilitação efetiva de forwarding do estágio MEM/WB.
	signal memwb_we_reg_fwd   : std_logic;
	-- Seletor de forwarding de 2 bits para o operando rs1.
	signal ex_forward_a       : std_logic_vector(1 downto 0);
	-- Seletor de forwarding de 2 bits para o operando rs2.
	signal ex_forward_b       : std_logic_vector(1 downto 0);
	-- Valor do operando rs1 após seleção de forwarding.
	signal ex_fwd_rs1_val     : word_t;
	-- Valor do operando rs2 após seleção de forwarding.
	signal ex_fwd_rs2_val     : word_t;
	-- Primeiro operando entregue à entrada i_a da ULA.
	signal ex_alu_op_a        : word_t;
	-- Segundo operando entregue à entrada i_b da ULA.
	signal ex_alu_op_b        : word_t;
	-- Resultado calculado pela ULA principal.
	signal ex_alu_result      : word_t;
	-- Flag de condição de desvio calculada pela ULA principal.
	signal ex_alu_branch_flag : std_logic;
	-- Resultado de 32 bits produzido pela unidade multdiv.
	signal ex_muldiv_result   : word_t;

	-- Sinais internos da extensão Zicsr e Trap Unit.
	signal csr_commit         : std_logic;
	-- Pulso de exceção entregue ao banco de CSRs: a deste estágio ou a do estágio MEM.
	signal csr_trap_take      : std_logic;
	-- Causa da exceção entregue ao banco de CSRs.
	signal csr_trap_cause     : word_t;
	-- PC da instrução que gerou a exceção entregue ao banco de CSRs.
	signal csr_trap_pc        : word_t;
	-- Valor de mtval da exceção entregue ao banco de CSRs.
	signal csr_trap_tval      : word_t;
	-- Indica que o campo rs1/zimm da instrução CSR é igual a zero.
	signal csr_src_zero       : std_logic;
	-- Dado de 32 bits para escrita/modificação no CSR.
	signal csr_wdata          : word_t;
	-- Valor antigo lido do registrador CSR selecionado.
	signal csr_rdata          : word_t;
	-- Indica acesso ilegal a registrador CSR.
	signal csr_illegal        : std_logic;
	-- Pulso interno de tomada de trap síncrono.
	signal trap_take_int      : std_logic;
	-- Exceção detectada sem Zicsr: sinalizada na saída, sem redirecionar o PC.
	signal sig_take           : std_logic;
	-- Causa da exceção sinalizada sem Zicsr.
	signal sig_cause          : word_t;
	-- Valor adicional da exceção sinalizada sem Zicsr (não exportado: o core sem CSRs não tem mtval).
	signal sig_tval           : word_t;
	-- Saída de MRET do detector sem Zicsr (descartada: sem modo M não há retorno de trap).
	signal sig_mret           : std_logic;
	-- Pulso interno de retorno de trap (MRET).
	signal mret_take_int      : std_logic;
	-- Código da causa da exceção síncrona.
	signal trap_cause         : word_t;
	-- Valor informativo da exceção síncrona (mtval).
	signal trap_tval          : word_t;
	-- Endereço do tratador de trap armazenado em mtvec.
	signal csr_mtvec          : word_t;
	-- Endereço de retorno de trap armazenado em mepc.
	signal csr_mepc           : word_t;
	-- Indica que houve desvio ou salto tomado na instrução atual em EX.
	signal ex_cf_taken        : std_logic;
	-- Endereço alvo do desvio ou salto tomado em EX.
	signal ex_cf_target       : word_t;
	-- Bit 1 do alvo de JALR, calculado só dos dois bits baixos dos operandos (sem esperar a soma de 32 bits da ULA).
	signal jalr_target_bit1   : std_logic;
	-- Bit 1 do alvo do desvio ou salto tomado, disponível cedo.
	signal ex_cf_bit1         : std_logic;
	-- Bits de 31 a 2 do alvo do desvio ou salto tomado.
	signal ex_cf_target_hi    : std_logic_vector(31 downto 2);

	-- Pulso interno de conclusão de FENCE.I.
	signal fencei_take_int    : std_logic;

	-- Resultado selecionado entre ULA, MulDiv e CSR antes do mux de PC + 4.
	signal ex_alu_mux_result  : word_t;

	-- Sinais internos de cálculo de endereço e decisão de branch/JAL/JALR.
	signal branch_target_int  : word_t;
	-- Decisão interna de desvio condicional ou JAL tomado.
	signal branch_taken_int   : std_logic;
	-- Decisão interna de salto JALR tomado.
	signal jalr_taken_int     : std_logic;

begin

	-- =========================================================================
	-- Unidade de Forwarding e Muxes de Operandos
	-- =========================================================================
	exmem_we_reg_fwd <= i_exmem_we_reg and i_exmem_valid;
	memwb_we_reg_fwd <= i_memwb_we_reg and i_memwb_valid;

	u_forwarding_unit : entity work.forwarding_unit
		port map (
			i_ex_rs1       => i_rs1_idx,
			i_ex_rs2       => i_rs2_idx,
			i_exmem_rd     => i_exmem_rd,
			i_exmem_we_reg => exmem_we_reg_fwd,
			i_memwb_rd     => i_memwb_rd,
			i_memwb_we_reg => memwb_we_reg_fwd,
			i_wb2_rd       => i_wb2_rd,
			i_wb2_we_reg   => i_wb2_we_reg,
			o_fwd_rs1      => ex_forward_a,
			o_fwd_rs2      => ex_forward_b
		);

	u_mux_fwd_rs1 : entity work.mux_4x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => i_rs1_val,
			i_d1  => i_memwb_alu_out,
			i_d2  => i_exmem_alu_out,
			i_d3  => i_wb2_data,
			i_sel => ex_forward_a,
			o_d   => ex_fwd_rs1_val
		);

	u_mux_fwd_rs2 : entity work.mux_4x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => i_rs2_val,
			i_d1  => i_memwb_alu_out,
			i_d2  => i_exmem_alu_out,
			i_d3  => i_wb2_data,
			i_sel => ex_forward_b,
			o_d   => ex_fwd_rs2_val
		);

	u_mux_alu_a : entity work.mux_2x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => i_pc,
			i_d1  => ex_fwd_rs1_val,
			i_sel => i_sel_pc_rs1,
			o_d   => ex_alu_op_a
		);

	u_mux_alu_b : entity work.mux_2x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => ex_fwd_rs2_val,
			i_d1  => i_imm,
			i_sel => i_sel_rs2_imm,
			o_d   => ex_alu_op_b
		);

	-- =========================================================================
	-- ULA Principal
	-- =========================================================================
	u_alu : entity work.alu
		port map (
			i_op     => i_alu_op,
			i_res_sel => i_alu_sel,
			i_a      => ex_alu_op_a,
			i_b      => ex_alu_op_b,
			o_d      => ex_alu_result,
			o_branch => ex_alu_branch_flag
		);

	-- =========================================================================
	-- Extensão M: Multiplicação e Divisão Inteira (multdiv)
	-- =========================================================================
	gen_m : if (has_m or has_zmmul) generate
		u_muldiv : entity work.multdiv
			generic map (
				has_div => has_m
			)
			port map (
				i_clk       => i_clk,
				i_rst       => i_rst,
				i_valid     => i_valid,
				i_is_muldiv => i_is_muldiv,
				i_funct3    => i_funct3,
				i_a         => ex_fwd_rs1_val,
				i_b         => ex_fwd_rs2_val,
				o_result    => ex_muldiv_result,
				o_stall     => o_muldiv_stall,
				o_busy      => open,
				o_done      => open
			);
	else generate
		o_muldiv_stall   <= '0';
		ex_muldiv_result <= (others => '0');
	end generate gen_m;

	-- =========================================================================
	-- Extensão Zifencei: Sincronização de Memória de Instruções (FENCE.I)
	-- =========================================================================
	gen_fencei : if has_zifencei generate
		u_fencei : entity work.fencei_unit
			generic map (
				has_dcache => has_dcache
			)
			port map (
				i_clk       => i_clk,
				i_rst       => i_rst,
				i_ex_valid  => i_valid,
				i_run       => i_base_run,
				i_opcode    => i_opcode,
				i_funct3    => i_funct3,
				i_dc_done   => i_dc_done,
				o_flush_req => o_dc_flush,
				o_busy      => o_fencei_busy,
				o_take      => fencei_take_int
			);
	else generate
		fencei_take_int <= '0';
		o_fencei_busy   <= '0';
		o_dc_flush      <= '0';
	end generate gen_fencei;

	o_fencei_take <= fencei_take_int;

	-- =========================================================================
	-- Extensão Zicsr e Detecção de Traps do Modo Máquina
	-- =========================================================================
	gen_csr : if has_zicsr generate
		-- A exceção do estágio MEM é de uma instrução mais antiga: vale no lugar da deste estágio.
		csr_trap_take  <= trap_take_int or i_mem_trap_take;
		csr_trap_cause <= i_mem_trap_cause when i_mem_trap_take = '1' else trap_cause;
		csr_trap_pc    <= i_mem_trap_pc    when i_mem_trap_take = '1' else i_pc;
		csr_trap_tval  <= i_mem_trap_tval  when i_mem_trap_take = '1' else trap_tval;

		csr_commit   <= i_is_csr and i_valid and i_pipe_run;
		csr_src_zero <= '1' when i_rs1_idx = REG_ZERO else '0';
		csr_wdata    <= ex_fwd_rs1_val when i_funct3(2) = '0' else
		                (31 downto 5 => '0') & i_rs1_idx;

		u_csr_file : entity work.csr_file
			generic map (
				has_m       => has_m,
				has_zicntr  => has_zicntr,
				tick_cycles => tick_cycles,
				hpm_counters => hpm_counters
			)
			port map (
				i_clk        => i_clk,
				i_rst        => i_rst,
				i_commit     => csr_commit,
				i_addr       => i_imm(11 downto 0),
				i_op         => i_funct3,
				i_wdata      => csr_wdata,
				i_src_zero   => csr_src_zero,
				o_rdata      => csr_rdata,
				o_illegal    => csr_illegal,
				i_trap_take  => csr_trap_take,
				i_trap_cause => csr_trap_cause,
				i_trap_pc    => csr_trap_pc,
				i_trap_tval  => csr_trap_tval,
				i_mret_take  => mret_take_int,
				i_retire     => i_retire,
				i_retire_cancel => i_mem_trap_take,
				i_events     => i_hpm_events,
				o_mtvec      => csr_mtvec,
				o_mepc       => csr_mepc
			);

		-- O alvo desalinhado depende só do bit 1 do alvo, porque o bit 0 é zero: no JALR ele sai da soma dos dois
		-- bits baixos de rs1 e do imediato, e no desvio e no JAL, do somador de PC mais imediato. O alvo completo
		-- (a soma da ULA) só alimenta mtval, então a causa 0 não espera a ULA.
		jalr_target_bit1 <= ex_alu_op_a(1) xor ex_alu_op_b(1) xor (ex_alu_op_a(0) and ex_alu_op_b(0));
		ex_cf_bit1       <= jalr_target_bit1 when jalr_taken_int = '1' else branch_target_int(1);
		ex_cf_target_hi  <= ex_alu_result(31 downto 2) when jalr_taken_int = '1' else branch_target_int(31 downto 2);

		ex_cf_taken  <= branch_taken_int or jalr_taken_int;
		ex_cf_target <= ex_cf_target_hi & ex_cf_bit1 & '0';

		sig_take  <= '0';
		sig_cause <= (others => '0');
		sig_tval  <= (others => '0');
		sig_mret  <= '0';

		u_trap_unit : entity work.trap_unit
			generic map (
				has_zicclsm => has_zicclsm,
				check_ea    => false
			)
			port map (
				i_ex_valid    => i_valid,
				i_run         => i_pipe_run,
				i_opcode      => i_opcode,
				i_funct3      => i_funct3,
				i_rd_idx      => i_rd_idx,
				i_rs1_idx     => i_rs1_idx,
				i_imm12       => i_imm(11 downto 0),
				i_ea          => (others => '0'),
				i_cf_taken    => ex_cf_taken,
				i_cf_target   => ex_cf_target,
				i_csr_illegal => csr_illegal,
				i_illegal     => i_illegal,
				o_take        => trap_take_int,
				o_mret_take   => mret_take_int,
				o_cause       => trap_cause,
				o_tval        => trap_tval
			);
	else generate
		-- Sem CSRs o detector só sinaliza: qualquer instrução CSR é ilegal e um desvio desalinhado não é checado.
		u_trap_detect : entity work.trap_unit
			generic map (
				has_zicclsm => has_zicclsm,
				check_ea    => true
			)
			port map (
				i_ex_valid    => i_valid,
				i_run         => i_pipe_run,
				i_opcode      => i_opcode,
				i_funct3      => i_funct3,
				i_rd_idx      => i_rd_idx,
				i_rs1_idx     => i_rs1_idx,
				i_imm12       => i_imm(11 downto 0),
				i_ea          => ex_alu_result,
				i_cf_taken    => '0',
				i_cf_target   => (others => '0'),
				i_csr_illegal => '1',
				i_illegal     => i_illegal,
				o_take        => sig_take,
				o_mret_take   => sig_mret,
				o_cause       => sig_cause,
				o_tval        => sig_tval
			);

		trap_take_int <= '0';
		mret_take_int <= '0';
		trap_cause    <= (others => '0');
		trap_tval     <= (others => '0');
		csr_mtvec     <= (others => '0');
		csr_mepc      <= (others => '0');
		ex_cf_taken   <= '0';
		ex_cf_target  <= (others => '0');
		csr_commit    <= '0';
		csr_src_zero  <= '0';
		csr_wdata     <= (others => '0');
		csr_rdata     <= (others => '0');
		csr_illegal   <= '0';
	end generate gen_csr;

	o_trap_take   <= trap_take_int;
	o_trap_sig       <= sig_take;
	o_trap_sig_cause <= sig_cause when sig_take = '1' else (others => '0');
	o_trap_sig_pc    <= i_pc      when sig_take = '1' else (others => '0');
	o_mret_take   <= mret_take_int;

	o_redirect_pc <= csr_mepc when mret_take_int   = '1' else
	                 i_pc4    when fencei_take_int = '1' else
	                 csr_mtvec;

	-- =========================================================================
	-- Seleção do Resultado de Execução e Cálculo de Desvios / Store Manager
	-- =========================================================================
	ex_alu_mux_result <= ex_muldiv_result when i_is_muldiv = '1' else
	                     csr_rdata        when i_is_csr    = '1' else
	                     ex_alu_result;

	u_mux_ex_final : entity work.mux_2x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => ex_alu_mux_result,
			i_d1  => i_pc4,
			i_sel => i_sel_pc4_alu,
			o_d   => o_final_result
		);

	u_branch_target_adder : entity work.adder
		generic map (
			data_width => word_t'length
		)
		port map (
			i_a => i_pc,
			i_b => i_imm,
			o_d => branch_target_int
		);

	branch_taken_int <= (i_valid and ex_alu_branch_flag) when i_opcode = OPCODE_BRANCH else
	                    i_valid                          when i_opcode = OPCODE_JAL    else
	                    '0';

	jalr_taken_int   <= i_valid when i_opcode = OPCODE_JALR else '0';

	-- O endereço alvo de JALR ((rs1 + imm) & ~1) já é calculado por u_alu via ALU_JALR.
	o_branch_target  <= branch_target_int;
	o_jalr_target    <= ex_alu_result;
	o_branch_taken   <= branch_taken_int;
	o_jalr_taken     <= jalr_taken_int;

	u_store_manager : entity work.store_manager
		port map (
			i_opcode      => i_opcode,
			i_funct3      => i_funct3,
			i_byte_offset => ex_alu_result(1 downto 0),
			i_rs2_data    => ex_fwd_rs2_val,
			o_data        => o_store_data,
			o_byte_mask   => o_store_byte_mask
		);

end architecture rtl;
