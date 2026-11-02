-- =============================================================================
-- Unidade integrada de multiplicação e divisão inteira (Extensão RV32M)
--
-- Coordena a execução das 8 instruções da extensão M no estágio EX (com
-- has_div = false, só as 4 multiplicações da extensão Zmmul, sem o divisor):
--   - Multiplicação (33 ciclos via booth_multiplier_rv32):
--     MUL (32 bits baixos), MULH (32 bits altos signed x signed),
--     MULHSU (32 bits altos signed x unsigned) e MULHU (32 bits altos unsigned x unsigned).
--   - Divisão e Resto (34 ciclos via non_restoring_divider_rv32):
--     DIV, DIVU, REM e REMU.
--
-- Gera internamente o pulso único de início (start_pulse) no primeiro ciclo em
-- que uma instrução válida da extensão M entra no estágio EX (i_valid = '1' e
-- i_is_muldiv = '1') e mantém o_stall = '1' durante toda a execução e no ciclo
-- de captura do resultado final (u_result_reg).
--
-- O stall é o OU do pulso de início (combinacional, para parar a instrução já no
-- primeiro ciclo) com um flip-flop que guarda o sinal de ocupado do ciclo anterior.
-- Esse flip-flop cobre os ciclos de cálculo e o de término, e assim o pulso de
-- término não entra na lógica de stall do pipeline.
--
-- Fusão de pares (recomendação do capítulo da extensão M): ao terminar, cada
-- operação grava num registro os dois operandos, o funct3 e o resultado completo
-- (produto de 64 bits ou o par resto e quociente). Se a instrução seguinte tem os
-- mesmos valores de operandos, é outra operação da mesma família (qualquer
-- multiplicação, ou DIV/REM, ou DIVU/REMU) e o registro é válido, ela não repete o
-- cálculo: no ciclo seguinte ao início a comparação acusa o acerto, a unidade em
-- curso é interrompida e o resultado sai do registro um ciclo depois. O stall dura
-- 3 ciclos (início, comparação e término). O acerto depende só dos valores, então é
-- sempre correto, quaisquer que sejam os registradores de origem e de destino.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.funct3_consts.all;
use work.muldiv_consts.all;

entity multdiv is
	generic (
		-- Instancia o divisor (extensão M completa); '0' deixa só a multiplicação (Zmmul).
		has_div     : boolean := true
	);
	port (
		-- Sinal de clock do sistema.
		i_clk       : in  std_logic;
		-- Sinal de reset ativo em '1'.
		i_rst       : in  std_logic := '0';
		-- Indica que há uma instrução válida no estágio EX.
		i_valid     : in  std_logic := '0';
		-- Indica que a instrução no estágio EX pertence à extensão M.
		i_is_muldiv : in  std_logic := '0';
		-- Código funct3 que seleciona a operação (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU).
		i_funct3    : in  funct3_t;
		-- Primeiro operando de 32 bits (rs1).
		i_a         : in  word_t;
		-- Segundo operando de 32 bits (rs2).
		i_b         : in  word_t;
		-- Resultado final de 32 bits registrado ao término da operação.
		o_result    : out word_t;
		-- Indica que o estágio EX deve permanecer em stall aguardando o resultado da extensão M.
		o_stall     : out std_logic;
		-- Indica que o multiplicador ou o divisor está em execução.
		o_busy      : out std_logic;
		-- Pulso de 1 ciclo indicando conclusão do cálculo.
		o_done      : out std_logic;
		-- Pulso de 1 ciclo no ciclo de término de uma operação fundida (resultado tirado do registro).
		o_fused     : out std_logic
	);
end entity multdiv;

architecture rtl of multdiv is

	-- Estado registrado que indica que a instrução M atual no estágio EX já recebeu o pulso de partida.
	signal started_q      : std_logic := '0';
	-- Próximo estado do flip-flop started_q.
	signal started_nxt    : std_logic;
	-- Pulso de 1 ciclo que inicia o multiplicador ou divisor no primeiro ciclo da instrução M em EX.
	signal start_pulse    : std_logic;
	-- Sinal interno de stall (ativo enquanto busy = '1' ou done = '1').
	signal stall_int      : std_logic;
	-- Cópia registrada de busy_int: vale '1' do ciclo seguinte ao início até o ciclo de término (inclusive).
	signal active_q       : std_logic;
	-- Parte do stall que sobe no mesmo ciclo do início (eager stall), antes de active_q subir.
	signal eager_stall    : std_logic;

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
	signal signed_mode    : signed_mode_t;

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
	-- Sinal interno de ocupação combinando multiplicador e divisor.
	signal busy_int       : std_logic;
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

	-- Metade baixa do resultado completo da última operação (MUL baixo ou quociente), guardada na fusão.
	signal rec_lo         : word_t;
	-- Metade alta do resultado completo da última operação (produto alto sem correção ou resto).
	signal rec_hi         : word_t;
	-- Metade baixa do resultado completo da operação que termina, a gravar no registro.
	signal full_lo        : word_t;
	-- Metade alta do resultado completo da operação que termina, a gravar no registro.
	signal full_hi        : word_t;
	-- Acerto registrado da fusão: '1' no ciclo de término da operação fundida.
	signal fuse_q         : std_logic;
	-- Próximo valor do flip-flop de ocupado (o acerto zera o ocupado do ciclo de término).
	signal active_nxt     : std_logic;
	-- Parte baixa do produto escolhida entre o multiplicador e o registro.
	signal mul_lo_src     : word_t;
	-- Parte alta do produto escolhida entre o multiplicador e o registro.
	signal mul_hi_src     : word_t;
	-- Quociente escolhido entre o divisor e o registro.
	signal div_q_src      : word_t;
	-- Resto escolhido entre o divisor e o registro.
	signal div_r_src      : word_t;
	-- Habilita a gravação do resultado: término normal ou término fundido.
	signal result_we      : std_logic;

begin

	-- Geração de pulso único de partida por instrução M no estágio EX.
	start_pulse <= i_is_muldiv and i_valid and (not started_q);
	started_nxt <= '0' when stall_int = '0' else '1';

	u_started_ff : entity work.flip_flop
		port map (
			i_d      => started_nxt,
			o_d      => started_q,
			i_enable => '1',
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	-- Decodificação combinacional do funct3 de entrada para disparo imediato (start/busy).
	is_mult     <= '1' when i_funct3(2) = '0' else '0';
	is_unsigned <= '1' when (i_funct3 = FUNCT3_DIVU or i_funct3 = FUNCT3_REMU) else '0';

	start_mul   <= start_pulse and is_mult;
	start_div   <= start_pulse and (not is_mult);

	-- Registrador que preserva o funct3 da instrução iniciada durante todos os ciclos de cálculo.
	u_funct3_reg : entity work.generic_register
		generic map (
			data_width => funct3_t'length
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => start_pulse,
			i_d      => i_funct3,
			o_d      => funct3_latched
		);

	-- Decodificação baseada no funct3 registrado (estável no ciclo de término done_int).
	is_mult_lat   <= '1' when funct3_latched(2) = '0' else '0';
	is_mul_hi_lat <= '0' when funct3_latched = FUNCT3_MUL else '1';
	is_rem_lat    <= '1' when (funct3_latched = FUNCT3_REM or funct3_latched = FUNCT3_REMU) else '0';

	with funct3_latched select
		signed_mode <=
			SIGNED_BOTH   when FUNCT3_MUL | FUNCT3_MULH | FUNCT3_DIV | FUNCT3_REM,
			SIGNED_A_ONLY when FUNCT3_MULHSU,
			SIGNED_NONE   when others;

	busy_int  <= mult_busy or div_busy;
	done_int  <= mult_done or div_done;

	-- O stall é o início combinacional (um ciclo) seguido de um flip-flop que cobre os ciclos de
	-- cálculo e o de término. Assim o pulso de término não atravessa a lógica de stall do pipeline.
	eager_stall <= start_pulse;
	stall_int   <= eager_stall or active_q or fuse_q;

	-- Num acerto a unidade em curso é interrompida no ciclo de término, e o ocupado desse ciclo não se repete.
	active_nxt  <= busy_int and (not fuse_q);

	u_active_ff : entity work.flip_flop
		port map (
			i_d      => active_nxt,
			o_d      => active_q,
			i_enable => '1',
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	o_busy    <= busy_int;
	o_done    <= done_int;
	o_stall   <= stall_int;
	o_fused   <= fuse_q;

	-- Instância única do multiplicador de Booth radix-2 de 32 bits.
	u_booth_multiplier : entity work.booth_multiplier_rv32
		port map (
			i_clk          => i_clk,
			i_rst          => i_rst,
			i_start        => start_mul,
			i_abort        => fuse_q,
			i_multiplicand => i_a,
			i_multiplier   => i_b,
			o_result_lo    => mul_lo,
			o_result_hi    => mul_hi,
			o_done         => mult_done,
			o_busy         => mult_busy
		);

	-- Instância única do divisor não-restaurador de 32 bits (atende signed e unsigned).
	gen_divider : if has_div generate
		u_divider : entity work.non_restoring_divider_rv32
			port map (
				i_clk         => i_clk,
				i_rst         => i_rst,
				i_start       => start_div,
				i_abort       => fuse_q,
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
	else generate
		div_quotient  <= (others => '0');
		div_remainder <= (others => '0');
		div_done      <= '0';
		div_busy      <= '0';
	end generate gen_divider;

	-- Correção da parte alta para operandos sem sinal (MULHSU / MULHU).
	corr_a <= i_b when (i_a(31) = '1' and signed_mode(1) = '0') else (others => '0');
	corr_b <= i_a when (i_b(31) = '1' and signed_mode(0) = '0') else (others => '0');

	u_adder_corr_a : entity work.adder
		generic map (
			data_width => word_t'length
		)
		port map (
			i_a => mul_hi_src,
			i_b => corr_a,
			o_d => high_plus_a
		);

	u_adder_corr_b : entity work.adder
		generic map (
			data_width => word_t'length
		)
		port map (
			i_a => high_plus_a,
			i_b => corr_b,
			o_d => high_corrected
		);

	u_mux_mul_res : entity work.mux_2x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => mul_lo_src,
			i_d1  => high_corrected,
			i_sel => is_mul_hi_lat,
			o_d   => mul_result
		);

	u_mux_div_res : entity work.mux_2x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => div_q_src,
			i_d1  => div_r_src,
			i_sel => is_rem_lat,
			o_d   => div_result
		);

	u_mux_final_res : entity work.mux_2x1
		generic map (
			data_width => word_t'length
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
			data_width => word_t'length
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => result_we,
			i_d      => result_mux,
			o_d      => o_result
		);

	result_we <= done_int or fuse_q;

	-- =========================================================================
	-- Fusão de pares: registro da última operação e comparação por valor
	-- =========================================================================

	-- Resultado completo da operação que termina: produto de 64 bits ou o par resto e quociente.
	u_mux_full_lo : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => div_quotient,
			i_d1  => mul_lo,
			i_sel => is_mult_lat,
			o_d   => full_lo
		);

	u_mux_full_hi : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => div_remainder,
			i_d1  => mul_hi,
			i_sel => is_mult_lat,
			o_d   => full_hi
		);

	u_fusion : entity work.muldiv_fusion
		port map (
			i_clk         => i_clk,
			i_rst         => i_rst,
			i_start       => start_pulse,
			i_done        => done_int,
			i_funct3      => i_funct3,
			i_done_funct3 => funct3_latched,
			i_a           => i_a,
			i_b           => i_b,
			i_full_lo     => full_lo,
			i_full_hi     => full_hi,
			o_hit         => open,
			o_fuse        => fuse_q,
			o_rec_lo      => rec_lo,
			o_rec_hi      => rec_hi
		);

	-- No término fundido o resultado completo vem do registro, no lugar das unidades interrompidas.
	u_mux_mul_lo_src : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => mul_lo,
			i_d1  => rec_lo,
			i_sel => fuse_q,
			o_d   => mul_lo_src
		);

	u_mux_mul_hi_src : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => mul_hi,
			i_d1  => rec_hi,
			i_sel => fuse_q,
			o_d   => mul_hi_src
		);

	u_mux_div_q_src : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => div_quotient,
			i_d1  => rec_lo,
			i_sel => fuse_q,
			o_d   => div_q_src
		);

	u_mux_div_r_src : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => div_remainder,
			i_d1  => rec_hi,
			i_sel => fuse_q,
			o_d   => div_r_src
		);

end architecture rtl;
