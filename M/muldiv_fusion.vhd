-- =============================================================================
-- Registro de fusão de pares da unidade de multiplicação e divisão (RV32M)
--
-- O capítulo da extensão M recomenda executar uma só vez MULH[[S]U] seguido de MUL
-- e DIV[U] seguido de REM[U] com os mesmos operandos. Esta entidade guarda a última
-- operação concluída (os dois operandos, o funct3 e o resultado completo: produto de
-- 64 bits ou o par resto e quociente) e acusa um acerto quando a instrução seguinte
--   - tem os mesmos valores de operandos (a comparação é por valor, e não por nome de
--     registrador, e por isso o acerto é sempre correto);
--   - é da mesma família: qualquer multiplicação, DIV/REM (com sinal) ou DIVU/REMU
--     (sem sinal);
--   - é outra operação, e não a repetição da registrada.
--
-- A comparação ocorre no ciclo seguinte ao pulso de início, quando os operandos já
-- estão travados no estágio EX. o_fuse sobe no ciclo seguinte (ciclo de término) e
-- vale '1' por um ciclo; nesse ciclo o resultado completo está em o_rec_lo e o_rec_hi.
-- O registro só muda quando uma operação termina por inteiro (i_done), e é válido a
-- partir da primeira; a única invalidação é o reset.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

entity muldiv_fusion is
	port (
		-- Sinal de clock do sistema.
		i_clk         : in  std_logic;
		-- Sinal de reset ativo em '1'.
		i_rst         : in  std_logic := '0';
		-- Pulso de início de uma instrução M no estágio EX (primeiro ciclo dela).
		i_start       : in  std_logic;
		-- Pulso de término de uma operação executada por inteiro (grava o registro).
		i_done        : in  std_logic;
		-- funct3 da instrução atual no estágio EX.
		i_funct3      : in  funct3_t;
		-- funct3 da operação que termina (o travado no início dela).
		i_done_funct3 : in  funct3_t;
		-- Operando A (rs1) da instrução atual.
		i_a           : in  word_t;
		-- Operando B (rs2) da instrução atual.
		i_b           : in  word_t;
		-- Metade baixa do resultado completo da operação que termina (MUL baixo ou quociente).
		i_full_lo     : in  word_t;
		-- Metade alta do resultado completo da operação que termina (produto alto ou resto).
		i_full_hi     : in  word_t;
		-- Acerto no ciclo de comparação (combinacional).
		o_hit         : out std_logic;
		-- Acerto registrado: '1' no ciclo de término da operação fundida.
		o_fuse        : out std_logic;
		-- Metade baixa do resultado completo guardado.
		o_rec_lo      : out word_t;
		-- Metade alta do resultado completo guardado.
		o_rec_hi      : out word_t
	);
end entity muldiv_fusion;

architecture rtl of muldiv_fusion is

	-- '1' depois que alguma operação terminou.
	signal rec_valid     : std_logic;
	-- Operando A da última operação concluída.
	signal rec_a         : word_t;
	-- Operando B da última operação concluída.
	signal rec_b         : word_t;
	-- funct3 da última operação concluída.
	signal rec_funct3    : funct3_t;
	-- Ciclo seguinte ao início de uma instrução M: o ciclo em que a comparação é feita.
	signal check_q       : std_logic;
	-- Os operandos atuais são iguais aos do registro.
	signal same_operands : std_logic;
	-- A operação atual é da mesma família da registrada e diferente dela.
	signal pair_ops      : std_logic;
	-- Acerto combinacional do ciclo de comparação.
	signal hit           : std_logic;

begin

	u_rec_a : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => i_done,
			i_d      => i_a,
			o_d      => rec_a
		);

	u_rec_b : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => i_done,
			i_d      => i_b,
			o_d      => rec_b
		);

	u_rec_funct3 : entity work.generic_register
		generic map (
			data_width => 3
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => i_done,
			i_d      => i_done_funct3,
			o_d      => rec_funct3
		);

	u_rec_lo : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => i_done,
			i_d      => i_full_lo,
			o_d      => o_rec_lo
		);

	u_rec_hi : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => i_done,
			i_d      => i_full_hi,
			o_d      => o_rec_hi
		);

	u_rec_valid : entity work.flip_flop
		port map (
			i_d      => '1',
			o_d      => rec_valid,
			i_enable => i_done,
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	u_check_ff : entity work.flip_flop
		port map (
			i_d      => i_start,
			o_d      => check_q,
			i_enable => '1',
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	same_operands <= '1' when (i_a = rec_a and i_b = rec_b) else '0';

	-- Mesma família (multiplicação, divisão com sinal ou divisão sem sinal) e operação diferente da registrada.
	pair_ops <= '1' when (i_funct3 /= rec_funct3 and
	                      i_funct3(2) = rec_funct3(2) and
	                      (i_funct3(2) = '0' or i_funct3(0) = rec_funct3(0))) else '0';

	hit   <= check_q and rec_valid and same_operands and pair_ops;
	o_hit <= hit;

	u_fuse_ff : entity work.flip_flop
		port map (
			i_d      => hit,
			o_d      => o_fuse,
			i_enable => '1',
			i_clk    => i_clk,
			i_rst    => i_rst
		);

end architecture rtl;
