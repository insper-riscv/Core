-- =============================================================================
-- Unidade integrada de multiplicação e divisão inteira (Extensão RV32M)
--
-- Coordena a execução das 8 instruções da extensão M no estágio EX:
--   - Multiplicação (33 ciclos via booth_multiplier_rv32):
--     MUL (32 bits baixos), MULH (32 bits altos signed x signed),
--     MULHSU (32 bits altos signed x unsigned) e MULHU (32 bits altos unsigned x unsigned).
--   - Divisão e Resto (34 ciclos via non_restoring_divider_rv32):
--     DIV, DIVU, REM e REMU.
--
-- Registra a operação iniciada (funct3_latched) no pulso de i_start e captura o
-- resultado final (result_latched) no pulso de conclusão (done_int) usando
-- instâncias estruturais de generic_register.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.funct3_consts.all;

entity multdiv is
	port (
		-- Sinal de clock do sistema.
		i_clk    : in  std_logic;
		-- Sinal de reset ativo em '1'.
		i_rst    : in  std_logic := '0';
		-- Pulso de 1 ciclo que inicia a operação da extensão M no estágio EX.
		i_start  : in  std_logic := '0';
		-- Código funct3 que seleciona a operação (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU).
		i_funct3 : in  funct3_t;
		-- Primeiro operando de 32 bits (rs1).
		i_a      : in  word_t;
		-- Segundo operando de 32 bits (rs2).
		i_b      : in  word_t;
		-- Resultado final de 32 bits registrado ao término da operação.
		o_result : out word_t;
		-- Indica que o multiplicador ou o divisor está em execução.
		o_busy   : out std_logic;
		-- Pulso de 1 ciclo indicando conclusão do cálculo.
		o_done   : out std_logic
	);
end entity multdiv;

architecture rtl of multdiv is

	-- Indica se o funct3 atual na entrada seleciona uma multiplicação (bit 2 = '0').
	signal is_mult        : std_logic;
	-- Indica se o funct3 atual seleciona divisão/resto sem sinal (DIVU ou REMU).
	signal is_unsigned    : std_logic;

	-- Pulso de partida direcionado exclusivamente ao multiplicador de Booth.
	signal start_mul      : std_logic;
	-- Pulso de partida direcionado exclusivamente ao divisor não-restaurador.
	signal start_div      : std_logic;

	-- Código funct3 travado no início da operação (garante seleção estável ao concluir).
	signal funct3_latched : funct3_t;
	-- Indica se a operação travada é uma multiplicação.
	signal is_mult_lat    : std_logic;
	-- Indica se a operação travada seleciona parte alta do produto (MULH, MULHSU, MULHU).
	signal is_mul_hi_lat  : std_logic;
	-- Indica se a operação travada é de resto de divisão (REM, REMU).
	signal is_rem_lat     : std_logic;
	-- Modo de sinal dos operandos A e B ("11"=signed/signed, "10"=signed/unsigned, "00"=unsigned/unsigned).
	signal signed_mode    : std_logic_vector(1 downto 0);

	-- Parte baixa (bits [31:0]) produzida pelo multiplicador de Booth.
	signal mul_lo         : word_t;
	-- Parte alta (bits [63:32]) produzida pelo multiplicador de Booth (interpretação signed).
	signal mul_hi         : word_t;
	-- Resultado selecionado da multiplicação (parte baixa ou alta corrigida).
	signal mul_result     : word_t;

	-- Quociente de 32 bits produzido pelo divisor não-restaurador.
	signal div_quotient   : word_t;
	-- Resto de 32 bits produzido pelo divisor não-restaurador.
	signal div_remainder  : word_t;
	-- Resultado selecionado da divisão (quociente ou resto).
	signal div_result     : word_t;

	-- Sinais de estado do multiplicador de Booth.
	signal mult_busy      : std_logic;
	-- Pulso de conclusão do multiplicador de Booth.
	signal mult_done      : std_logic;
	-- Sinais de estado do divisor não-restaurador.
	signal div_busy       : std_logic;
	-- Pulso de conclusão do divisor não-restaurador.
	signal div_done       : std_logic;
	-- Pulso interno de conclusão combinando multiplicador e divisor.
	signal done_int       : std_logic;

	-- Termo de correção unsigned para o operando A quando interpretado como sem sinal (MULHU).
	signal corr_a         : word_t;
	-- Termo de correção unsigned para o operando B quando interpretado como sem sinal (MULHSU e MULHU).
	signal corr_b         : word_t;
	-- Soma intermediária da parte alta com o termo de correção A.
	signal high_plus_a    : word_t;
	-- Parte alta do produto corrigida para modos sem sinal (MULHSU / MULHU).
	signal high_corrected : word_t;

	-- Resultado combinacional selecionado no ciclo em que done_int pulsa.
	signal result_mux     : word_t;

begin

	-- Decodificação combinacional do funct3 de entrada para disparo imediato (start/busy).
	is_mult     <= '1' when i_funct3(2) = '0' else '0';
	is_unsigned <= '1' when (i_funct3 = FUNCT3_DIVU or i_funct3 = FUNCT3_REMU) else '0';

	start_mul   <= i_start and is_mult;
	start_div   <= i_start and (not is_mult);

	-- Registrador que preserva o funct3 da instrução iniciada durante todos os ciclos de cálculo.
	u_funct3_reg : entity work.generic_register
		generic map (
			data_width => 3
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => i_start,
			i_d      => i_funct3,
			o_d      => funct3_latched
		);

	-- Decodificação baseada no funct3 registrado (estável no ciclo de término done_int).
	is_mult_lat   <= '1' when funct3_latched(2) = '0' else '0';
	is_mul_hi_lat <= '0' when funct3_latched = FUNCT3_MUL else '1';
	is_rem_lat    <= '1' when (funct3_latched = FUNCT3_REM or funct3_latched = FUNCT3_REMU) else '0';

	with funct3_latched select
		signed_mode <=
			"11" when FUNCT3_MUL | FUNCT3_MULH | FUNCT3_DIV | FUNCT3_REM,
			"10" when FUNCT3_MULHSU,
			"00" when others;

	o_busy   <= mult_busy or div_busy;
	done_int <= mult_done or div_done;
	o_done   <= done_int;

	-- Instância única do multiplicador de Booth radix-2 de 32 bits.
	u_booth_multiplier : entity work.booth_multiplier_rv32
		port map (
			i_clk          => i_clk,
			i_rst          => i_rst,
			i_start        => start_mul,
			i_multiplicand => i_a,
			i_multiplier   => i_b,
			o_result_lo    => mul_lo,
			o_result_hi    => mul_hi,
			o_done         => mult_done,
			o_busy         => mult_busy
		);

	-- Instância única do divisor não-restaurador de 32 bits (atende signed e unsigned).
	u_divider : entity work.non_restoring_divider_rv32
		port map (
			i_clk         => i_clk,
			i_rst         => i_rst,
			i_start       => start_div,
			i_is_unsigned => is_unsigned,
			i_dividend    => i_a,
			i_divisor     => i_b,
			o_quotient    => div_quotient,
			o_remainder   => div_remainder,
			o_done        => div_done,
			o_busy        => div_busy,
			o_div_by_zero => open,
			o_overflow    => open
		);

	-- Correção da parte alta para operandos sem sinal:
	-- Como o multiplicador de Booth opera em complemento de 2 (32x32 signed),
	-- se um operando X tem MSB = '1' mas a instrução o trata como unsigned,
	-- o produto signed subtraiu (2^32 * Y); somar Y na parte alta [63:32] restaura o valor unsigned.
	corr_a <= i_b when (i_a(31) = '1' and signed_mode(1) = '0') else (others => '0');
	corr_b <= i_a when (i_b(31) = '1' and signed_mode(0) = '0') else (others => '0');

	u_adder_corr_a : entity work.adder
		generic map (
			data_width => 32
		)
		port map (
			i_a => mul_hi,
			i_b => corr_a,
			o_d => high_plus_a
		);

	u_adder_corr_b : entity work.adder
		generic map (
			data_width => 32
		)
		port map (
			i_a => high_plus_a,
			i_b => corr_b,
			o_d => high_corrected
		);

	u_mux_mul_res : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => mul_lo,
			i_d1  => high_corrected,
			i_sel => is_mul_hi_lat,
			o_d   => mul_result
		);

	u_mux_div_res : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => div_quotient,
			i_d1  => div_remainder,
			i_sel => is_rem_lat,
			o_d   => div_result
		);

	u_mux_final_res : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => div_result,
			i_d1  => mul_result,
			i_sel => is_mult_lat,
			o_d   => result_mux
		);

	-- Registrador de captura do resultado final no pulso done_int.
	u_result_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => done_int,
			i_d      => result_mux,
			o_d      => o_result
		);

end architecture rtl;
