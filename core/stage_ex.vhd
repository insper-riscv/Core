-- =============================================================================
-- Estágio EX (Execute) do Pipeline RV32
--
-- Conecta estruturalmente as unidades funcionais de execução, adiantamento de
-- dados (forwarding), cálculo de desvios, gerenciador de escritas em memória e
-- unidades de extensão do estágio EX:
--   1. Unidade de adiantamento (forwarding_unit) e muxes de operandos rs1/rs2.
--   2. ULA principal (alu) e somadores de endereço-alvo de branch/JAL e JALR.
--   3. Unidade de multiplicação e divisão inteira (multdiv, quando has_m = true).
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
		-- Habilita a instância da unidade de multiplicação e divisão (multdiv).
		has_m        : boolean := false;
		-- Habilita o banco de registradores CSR e a unidade de traps (csr_file, trap_unit).
		has_zicsr    : boolean := false;
		-- Habilita a unidade de sincronização de cache de instruções (fencei_unit).
		has_zifencei : boolean := false;
		-- Habilita o handshake de flush com a cache de dados write-back em FENCE.I.
		has_dcache   : boolean := false
	);
	port (
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
		-- Indica que a instrução em EX pertence à extensão M (decodificado no ID).
		i_is_muldiv       : in  std_logic;
		-- Indica que a instrução em EX pertence à extensão Zicsr (decodificado no ID).
		i_is_csr          : in  std_logic;
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
		-- Dado final do estágio WB para adiantamento (forwarding).
		i_wb_data         : in  word_t;
		-- Confirmação de término do flush da cache de dados write-back (Zifencei).
		i_dc_done         : in  std_logic;
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

	component multdiv is
		port (
			i_clk       : in  std_logic;
			i_rst       : in  std_logic := '0';
			i_valid     : in  std_logic := '0';
			i_is_muldiv : in  std_logic := '0';
			i_funct3    : in  funct3_t;
			i_a         : in  word_t;
			i_b         : in  word_t;
			o_result    : out word_t;
			o_stall     : out std_logic;
			o_busy      : out std_logic;
			o_done      : out std_logic
		);
	end component;

	component csr_file is
		port (
			i_clk        : in  std_logic;
			i_rst        : in  std_logic;
			i_commit     : in  std_logic;
			i_addr       : in  std_logic_vector(11 downto 0);
			i_op         : in  funct3_t;
			i_wdata      : in  word_t;
			i_src_zero   : in  std_logic;
			o_rdata      : out word_t;
			o_illegal    : out std_logic;
			i_trap_take  : in  std_logic;
			i_trap_cause : in  word_t;
			i_trap_pc    : in  word_t;
			i_trap_tval  : in  word_t;
			i_mret_take  : in  std_logic;
			o_mtvec      : out word_t;
			o_mepc       : out word_t
		);
	end component;

	component trap_unit is
		port (
			i_ex_valid    : in  std_logic;
			i_run         : in  std_logic;
			i_opcode      : in  opcode_t;
			i_funct3      : in  funct3_t;
			i_rd_idx      : in  reg_t;
			i_rs1_idx     : in  reg_t;
			i_imm12       : in  std_logic_vector(11 downto 0);
			i_ea          : in  word_t;
			i_cf_taken    : in  std_logic;
			i_cf_target   : in  word_t;
			i_csr_illegal : in  std_logic;
			o_take        : out std_logic;
			o_mret_take   : out std_logic;
			o_cause       : out word_t;
			o_tval        : out word_t
		);
	end component;

	component fencei_unit is
		generic (
			has_dcache : boolean := false
		);
		port (
			i_clk       : in  std_logic;
			i_rst       : in  std_logic;
			i_ex_valid  : in  std_logic;
			i_run       : in  std_logic;
			i_opcode    : in  opcode_t;
			i_funct3    : in  funct3_t;
			i_dc_done   : in  std_logic;
			o_flush_req : out std_logic;
			o_busy      : out std_logic;
			o_take      : out std_logic
		);
	end component;

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
			o_fwd_rs1      => ex_forward_a,
			o_fwd_rs2      => ex_forward_b
		);

	u_mux_fwd_rs1 : entity work.mux_4x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => i_rs1_val,
			i_d1  => i_wb_data,
			i_d2  => i_exmem_alu_out,
			i_d3  => i_rs1_val,
			i_sel => ex_forward_a,
			o_d   => ex_fwd_rs1_val
		);

	u_mux_fwd_rs2 : entity work.mux_4x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => i_rs2_val,
			i_d1  => i_wb_data,
			i_d2  => i_exmem_alu_out,
			i_d3  => i_rs2_val,
			i_sel => ex_forward_b,
			o_d   => ex_fwd_rs2_val
		);

	u_mux_alu_a : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => i_pc,
			i_d1  => ex_fwd_rs1_val,
			i_sel => i_sel_pc_rs1,
			o_d   => ex_alu_op_a
		);

	u_mux_alu_b : entity work.mux_2x1
		generic map (
			data_width => 32
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
			i_a      => ex_alu_op_a,
			i_b      => ex_alu_op_b,
			o_d      => ex_alu_result,
			o_branch => ex_alu_branch_flag
		);

	-- =========================================================================
	-- Extensão M: Multiplicação e Divisão Inteira (multdiv)
	-- =========================================================================
	gen_m : if has_m generate
		u_muldiv : multdiv
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
		u_fencei : fencei_unit
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
		csr_commit   <= i_is_csr and i_valid and i_pipe_run;
		csr_src_zero <= '1' when i_rs1_idx = REG_ZERO else '0';
		csr_wdata    <= ex_fwd_rs1_val when i_funct3(2) = '0' else
		                (31 downto 5 => '0') & i_rs1_idx;

		u_csr_file : csr_file
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
				i_trap_take  => trap_take_int,
				i_trap_cause => trap_cause,
				i_trap_pc    => i_pc,
				i_trap_tval  => trap_tval,
				i_mret_take  => mret_take_int,
				o_mtvec      => csr_mtvec,
				o_mepc       => csr_mepc
			);

		ex_cf_taken  <= branch_taken_int or jalr_taken_int;
		ex_cf_target <= ex_alu_result when jalr_taken_int = '1' else branch_target_int;

		u_trap_unit : trap_unit
			port map (
				i_ex_valid    => i_valid,
				i_run         => i_pipe_run,
				i_opcode      => i_opcode,
				i_funct3      => i_funct3,
				i_rd_idx      => i_rd_idx,
				i_rs1_idx     => i_rs1_idx,
				i_imm12       => i_imm(11 downto 0),
				i_ea          => ex_alu_result,
				i_cf_taken    => ex_cf_taken,
				i_cf_target   => ex_cf_target,
				i_csr_illegal => csr_illegal,
				o_take        => trap_take_int,
				o_mret_take   => mret_take_int,
				o_cause       => trap_cause,
				o_tval        => trap_tval
			);
	else generate
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
			data_width => 32
		)
		port map (
			i_d0  => ex_alu_mux_result,
			i_d1  => i_pc4,
			i_sel => i_sel_pc4_alu,
			o_d   => o_final_result
		);

	u_branch_target_adder : entity work.adder
		generic map (
			data_width => 32
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
