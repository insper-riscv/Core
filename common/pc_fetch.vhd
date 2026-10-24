-- =============================================================================
-- Unidade de busca e atualização do Program Counter (estágio IF)
--
-- Mantém o registrador de Program Counter (PC), calcula combinacionalmente
-- PC + 4 via somador (adder) e seleciona o próximo endereço do PC via
-- multiplexador 4x1 (mux_4x1) de acordo com i_pc_src:
--   - PC_SRC_PC4      ("00") -> PC + 4 (fluxo sequencial normal)
--   - PC_SRC_BRANCH   ("01") -> i_branch_target (branch tomado ou JAL)
--   - PC_SRC_JALR     ("10") -> i_jalr_target (salto indireto JALR)
--   - PC_SRC_REDIRECT ("11") -> i_redirect_pc (trap, MRET ou FENCE.I; tem
--                               prioridade sobre congelamento de stall)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.pc_src_consts.all;

entity pc_fetch is

	port (
		-- Sinal de clock.
		i_clk           : in  std_logic;
		-- Sinal de reset síncrono ativo em '1'.
		i_rst           : in  std_logic;
		-- Habilita a atualização do registrador PC ('1' = avança, '0' = congela em stall).
		i_pc_we         : in  std_logic;
		-- Seletor de 2 bits da fonte do próximo PC (definido em pc_src_consts).
		i_pc_src        : in  pc_src_t;
		-- Endereço-alvo de desvio condicional ou JAL calculado no estágio EX (PC + imm).
		i_branch_target : in  word_t;
		-- Endereço-alvo de salto indireto JALR calculado no estágio EX ((rs1 + imm) & ~1).
		i_jalr_target   : in  word_t;
		-- Endereço de redirecionamento prioritário para trap, MRET ou FENCE.I.
		i_redirect_pc   : in  word_t := (others => '0');
		-- Valor atual do PC enviado ao barramento de busca e ao registrador IF/ID.
		o_pc            : out word_t;
		-- Valor de PC + 4 enviado ao registrador de estágio IF/ID.
		o_pc4           : out word_t
	);

end entity pc_fetch;

architecture rtl of pc_fetch is

	-- Incremento constante de 4 bytes por instrução de 32 bits.
	constant PC_STEP_4 : word_t := x"00000004";

	-- Valor atual armazenado no registrador de Program Counter.
	signal pc_reg   : word_t;
	-- Resultado combinacional da soma PC + 4.
	signal pc4_wire : word_t;
	-- Próximo endereço selecionado pelo multiplexador de entrada do PC.
	signal pc_next  : word_t;
	-- Habilitação efetiva de atualização do registrador PC.
	signal pc_en    : std_logic;

begin

	-- Somador combinacional para cálculo de PC + 4.
	u_pc4_adder : entity work.adder
		generic map (
			data_width => 32
		)
		port map (
			i_a => pc_reg,
			i_b => PC_STEP_4,
			o_d => pc4_wire
		);

	-- Multiplexador 4x1 de seleção do próximo valor do PC.
	u_pc_mux : entity work.mux_4x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => pc4_wire,
			i_d1  => i_branch_target,
			i_d2  => i_jalr_target,
			i_d3  => i_redirect_pc,
			i_sel => i_pc_src,
			o_d   => pc_next
		);

	pc_en <= '1' when (i_pc_we = '1' or i_pc_src = PC_SRC_REDIRECT) else '0';

	-- Registrador estrutural de 32 bits do Program Counter.
	u_pc_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => pc_en,
			i_d      => pc_next,
			o_d      => pc_reg
		);

	o_pc  <= pc_reg;
	o_pc4 <= pc4_wire;

end architecture rtl;
