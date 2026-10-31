-- =============================================================================
-- Multiplicador sequencial de Booth Radix-2 de 32 bits (Extensão RV32M)
--
-- Implementa o algoritmo de Booth radix-2 para multiplicação com sinal de
-- dois operandos de 32 bits (i_multiplicand e i_multiplier), produzindo um
-- produto de 64 bits dividido em parte baixa (o_result_lo, para MUL) e parte
-- alta (o_result_hi, para MULH/MULHSU/MULHU).
--
-- Latência: 33 ciclos de clock (1 ciclo de inicialização + 32 iterações).
-- Suporta toda a faixa com sinal de 32 bits, incluindo -2^31.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;

entity booth_multiplier_rv32 is
	port (
		-- Sinal de clock do sistema.
		i_clk          : in  std_logic;
		-- Sinal de reset síncrono ativo em '1'.
		i_rst          : in  std_logic;
		-- Pulso de início da multiplicação no estágio EX.
		i_start        : in  std_logic;
		-- Multiplicando de 32 bits (operando A / rs1).
		i_multiplicand : in  word_t;
		-- Multiplicador de 32 bits (operando B / rs2).
		i_multiplier   : in  word_t;
		-- Parte baixa do produto (bits [31:0], resultado da instrução MUL).
		o_result_lo    : out word_t;
		-- Parte alta do produto (bits [63:32], base para MULH/MULHSU/MULHU).
		o_result_hi    : out word_t;
		-- Pulso de 1 ciclo indicando que o produto de 64 bits está pronto.
		o_done         : out std_logic;
		-- Indica que o multiplicador está ocupado processando uma operação.
		o_busy         : out std_logic
	);
end entity booth_multiplier_rv32;

architecture rtl of booth_multiplier_rv32 is

	-- Estados da máquina de estados finitos do multiplicador de Booth.
	type state_t is (S_IDLE, S_COMPUTE, S_DONE);
	-- Estado atual da máquina de estados do multiplicador.
	signal state         : state_t := S_IDLE;

	-- Acumulador parcial superior de 33 bits (inclui bit extra de sinal).
	signal acc_reg       : signed(32 downto 0);
	-- Registrador de deslocamento do multiplicador de 32 bits.
	signal q_reg         : signed(31 downto 0);
	-- Bit extra à direita do multiplicador para codificação de Booth radix-2.
	signal q_minus1_reg  : std_logic;
	-- Multiplicando estendido com sinal para 33 bits.
	signal m_reg         : signed(32 downto 0);

	-- Contador de iterações (0 a 31, totalizando 32 passos).
	signal iter_count    : unsigned(5 downto 0);
	-- Registrador interno de ocupação durante os estados S_COMPUTE e S_DONE.
	signal busy_reg      : std_logic := '0';
	-- Inibidor que impede reinício imediato caso i_start permaneça em '1' ao final.
	signal start_inhibit : std_logic := '0';

begin

	-- Sinal o_busy sobe combinacionalmente no mesmo ciclo de i_start em S_IDLE (eager stall).
	o_busy <= '1' when (state = S_IDLE and i_start = '1' and start_inhibit = '0') else busy_reg;

	process(i_clk)
		-- Acumulador do próximo ciclo (33 bits: soma ou subtração do multiplicando com o acumulador atual).
		variable acc_next   : signed(32 downto 0);
		-- Concatenação acumulador, multiplicador e bit auxiliar de Booth (66 bits) antes do deslocamento aritmético.
		variable shift_conc : signed(65 downto 0);
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' then
				state        <= S_IDLE;
				acc_reg      <= (others => '0');
				q_reg        <= (others => '0');
				q_minus1_reg <= '0';
				m_reg        <= (others => '0');
				iter_count   <= (others => '0');
				o_done       <= '0';
				busy_reg     <= '0';
			else
				case state is

					when S_IDLE =>
						o_done <= '0';
						if i_start = '0' then
							start_inhibit <= '0';
						end if;
						if i_start = '1' and start_inhibit = '0' then
							acc_reg      <= (others => '0');
							q_reg        <= signed(i_multiplier);
							q_minus1_reg <= '0';
							m_reg        <= resize(signed(i_multiplicand), 33);
							iter_count   <= (others => '0');
							state        <= S_COMPUTE;
							busy_reg     <= '1';
						end if;

					when S_COMPUTE =>
						-- Codificação de Booth radix-2 sobre {q_reg(0), q_minus1_reg}:
						--   "01" -> soma o multiplicando (acc_reg + m_reg)
						--   "10" -> subtrai o multiplicando (acc_reg - m_reg)
						--   "00" ou "11" -> mantém o acumulador
						if q_reg(0) = '0' and q_minus1_reg = '1' then
							acc_next := acc_reg + m_reg;
						elsif q_reg(0) = '1' and q_minus1_reg = '0' then
							acc_next := acc_reg - m_reg;
						else
							acc_next := acc_reg;
						end if;

						-- Deslocamento aritmético de 1 bit à direita sobre {acc_next, q_reg, q_minus1_reg}.
						shift_conc   := shift_right(acc_next & q_reg & q_minus1_reg, 1);

						acc_reg      <= shift_conc(65 downto 33);
						q_reg        <= shift_conc(32 downto 1);
						q_minus1_reg <= shift_conc(0);

						if iter_count = to_unsigned(31, 6) then
							state <= S_DONE;
						else
							iter_count <= iter_count + 1;
						end if;

					when S_DONE =>
						o_done        <= '1';
						busy_reg      <= '0';
						start_inhibit <= '1';
						state         <= S_IDLE;

				end case;
			end if;
		end if;
	end process;

	o_result_hi <= std_logic_vector(acc_reg(31 downto 0));
	o_result_lo <= std_logic_vector(q_reg);

end architecture rtl;
