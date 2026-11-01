-- =============================================================================
-- Divisor sequencial não-restaurador de 32 bits (Extensão RV32M)
--
-- Suporta as 4 instruções de divisão inteira da especificação RISC-V RV32M:
--   - i_is_unsigned = '0': DIV e REM (divisão inteira com sinal, truncada em direção a zero)
--   - i_is_unsigned = '1': DIVU e REMU (divisão inteira sem sinal)
--
-- Casos especiais definidos pela especificação RISC-V:
--   - Divisão por zero (signed e unsigned): o_quotient = 0xFFFFFFFF, o_remainder = i_dividend
--   - Overflow com sinal (-2^31 / -1):      o_quotient = 0x80000000, o_remainder = 0x00000000
--
-- Latência: 34 ciclos para casos normais (1 init + 32 iterações + 1 correção + 1 ajuste de sinal)
--           e 2 ciclos para casos especiais (divisão por zero ou overflow).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.word_consts.all;

entity non_restoring_divider_rv32 is
	port (
		-- Sinal de clock do sistema.
		i_clk         : in  std_logic;
		-- Sinal de reset síncrono ativo em '1'.
		i_rst         : in  std_logic;
		-- Pulso de início da divisão no estágio EX.
		i_start       : in  std_logic;
		-- Pulso que interrompe a operação em curso e volta ao repouso, sem produzir o_done (resultado já conhecido).
		i_abort       : in  std_logic := '0';
		-- Modo de sinal da operação ('0' = DIV/REM com sinal, '1' = DIVU/REMU sem sinal).
		i_is_unsigned : in  std_logic;
		-- Dividendo de 32 bits (operando A / rs1).
		i_dividend    : in  word_t;
		-- Divisor de 32 bits (operando B / rs2).
		i_divisor     : in  word_t;
		-- Quociente de 32 bits calculado (resultado de DIV / DIVU).
		o_quotient    : out word_t;
		-- Resto de 32 bits calculado (resultado de REM / REMU).
		o_remainder   : out word_t;
		-- Pulso de 1 ciclo indicando que quociente e resto estão prontos.
		o_done        : out std_logic;
		-- Indica que o divisor está ocupado processando uma operação.
		o_busy        : out std_logic;
		-- Sinaliza que o divisor de entrada é igual a zero.
		o_div_by_zero : out std_logic;
		-- Sinaliza ocorrência de overflow na divisão com sinal (-2^31 / -1).
		o_overflow    : out std_logic
	);
end entity non_restoring_divider_rv32;

architecture rtl of non_restoring_divider_rv32 is

	-- Estados da máquina de estados finitos do divisor não-restaurador.
	type state_t is (S_IDLE, S_SPECIAL, S_COMPUTE, S_CORRECT, S_ADJUST_SIGN, S_DONE);
	-- Estado atual da máquina de estados do divisor.
	signal state              : state_t := S_IDLE;

	-- Resto parcial de 34 bits (33 bits de magnitude + 1 bit de sinal).
	signal rem_reg            : signed(33 downto 0);
	-- Registrador de deslocamento de 32 bits que acumula os bits do quociente.
	signal quot_reg           : unsigned(31 downto 0);
	-- Divisor absoluto estendido para 34 bits positivos.
	signal div_reg            : signed(33 downto 0);
	-- Contador de iterações (0 a 31).
	signal iter_count         : unsigned(5 downto 0);

	-- Armazena se o dividendo original era negativo no modo com sinal.
	signal dividend_neg       : std_logic;
	-- Armazena se o divisor original era negativo no modo com sinal.
	signal divisor_neg        : std_logic;
	-- Cópia registrada do modo sem sinal (i_is_unsigned) no início da operação.
	signal op_unsigned        : std_logic;

	-- Detecção combinacional de divisão por zero.
	signal detect_div_by_zero : std_logic;
	-- Detecção combinacional de overflow na divisão com sinal (-2^31 / -1).
	signal detect_overflow    : std_logic;

	-- Registrador de saída do quociente final.
	signal q_result           : word_t;
	-- Registrador de saída do resto final.
	signal r_result           : word_t;

	-- Registrador interno de ocupação durante o cálculo.
	signal busy_reg           : std_logic := '0';
	-- Inibidor que impede reinício imediato enquanto i_start permanecer em '1'.
	signal start_inhibit      : std_logic := '0';

begin

	-- Sinal o_busy sobe combinacionalmente no mesmo ciclo de i_start em S_IDLE (eager stall).
	o_busy <= '1' when (state = S_IDLE and i_start = '1' and start_inhibit = '0') else busy_reg;

	detect_div_by_zero <= '1' when unsigned(i_divisor) = 0 else '0';

	detect_overflow <= '1' when (i_is_unsigned = '0' and i_dividend = WORD_INT_MIN and i_divisor = WORD_ALL_ONES) else '0';

	process(i_clk)
		-- Resto parcial deslocado de um bit com o próximo bit do dividendo (34 bits com sinal).
		variable rem_shifted    : signed(33 downto 0);
		-- Resto parcial após somar ou subtrair o divisor (34 bits com sinal).
		variable rem_next       : signed(33 downto 0);
		-- Módulo do dividendo usado nas divisões com sinal.
		variable abs_dividend_v : unsigned(31 downto 0);
		-- Módulo do divisor usado nas divisões com sinal.
		variable abs_divisor_v  : unsigned(31 downto 0);
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' then
				state        <= S_IDLE;
				rem_reg      <= (others => '0');
				quot_reg     <= (others => '0');
				div_reg      <= (others => '0');
				iter_count   <= (others => '0');
				dividend_neg <= '0';
				divisor_neg  <= '0';
				op_unsigned  <= '0';
				o_done       <= '0';
				busy_reg     <= '0';
				q_result     <= (others => '0');
				r_result     <= (others => '0');
			elsif i_abort = '1' then
				state    <= S_IDLE;
				busy_reg <= '0';
				o_done   <= '0';
			else
				case state is

					when S_IDLE =>
						o_done <= '0';
						if i_start = '0' then
							start_inhibit <= '0';
						end if;
						if i_start = '1' and start_inhibit = '0' then
							op_unsigned <= i_is_unsigned;

							if detect_div_by_zero = '1' or detect_overflow = '1' then
								state    <= S_SPECIAL;
								busy_reg <= '1';

								if i_is_unsigned = '1' then
									dividend_neg <= '0';
									divisor_neg  <= '0';
								else
									dividend_neg <= i_dividend(31);
									divisor_neg  <= i_divisor(31);
								end if;
							else
								busy_reg <= '1';

								if i_is_unsigned = '1' then
									dividend_neg   <= '0';
									divisor_neg    <= '0';
									abs_dividend_v := unsigned(i_dividend);
									abs_divisor_v  := unsigned(i_divisor);
								else
									dividend_neg <= i_dividend(31);
									divisor_neg  <= i_divisor(31);

									if signed(i_dividend) < 0 then
										abs_dividend_v := unsigned(-signed(i_dividend));
									else
										abs_dividend_v := unsigned(i_dividend);
									end if;

									if signed(i_divisor) < 0 then
										abs_divisor_v := unsigned(-signed(i_divisor));
									else
										abs_divisor_v := unsigned(i_divisor);
									end if;
								end if;

								rem_reg    <= (others => '0');
								quot_reg   <= abs_dividend_v;
								div_reg    <= signed(resize(abs_divisor_v, div_reg'length));
								iter_count <= (others => '0');
								state      <= S_COMPUTE;
							end if;
						end if;

					when S_SPECIAL =>
						if detect_div_by_zero = '1' then
							q_result <= WORD_ALL_ONES;
							r_result <= i_dividend;
						else
							q_result <= WORD_INT_MIN;
							r_result <= (others => '0');
						end if;
						state <= S_DONE;

					when S_COMPUTE =>
						rem_shifted := rem_reg(32 downto 0) & quot_reg(31);

						if rem_shifted >= 0 then
							rem_next := rem_shifted - div_reg;
						else
							rem_next := rem_shifted + div_reg;
						end if;

						rem_reg <= rem_next;

						if rem_next >= 0 then
							quot_reg <= quot_reg(30 downto 0) & '1';
						else
							quot_reg <= quot_reg(30 downto 0) & '0';
						end if;

						if iter_count = to_unsigned(31, 6) then
							state <= S_CORRECT;
						else
							iter_count <= iter_count + 1;
						end if;

					when S_CORRECT =>
						if rem_reg < 0 then
							rem_reg <= rem_reg + div_reg;
						end if;
						state <= S_ADJUST_SIGN;

					when S_ADJUST_SIGN =>
						if op_unsigned = '1' then
							q_result <= std_logic_vector(quot_reg);
							r_result <= std_logic_vector(rem_reg(31 downto 0));
						else
							if (dividend_neg xor divisor_neg) = '1' then
								q_result <= std_logic_vector(-signed(quot_reg));
							else
								q_result <= std_logic_vector(quot_reg);
							end if;

							if dividend_neg = '1' then
								r_result <= std_logic_vector(-rem_reg(31 downto 0));
							else
								r_result <= std_logic_vector(rem_reg(31 downto 0));
							end if;
						end if;

						state <= S_DONE;

					when S_DONE =>
						o_done        <= '1';
						start_inhibit <= '1';
						busy_reg      <= '0';
						state         <= S_IDLE;

				end case;
			end if;
		end if;
	end process;

	o_quotient    <= q_result;
	o_remainder   <= r_result;
	o_div_by_zero <= detect_div_by_zero;
	o_overflow    <= detect_overflow;

end architecture rtl;
