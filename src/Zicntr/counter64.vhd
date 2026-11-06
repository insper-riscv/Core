-- =============================================================================
-- Contador de até 64 bits em duas metades, com vai-um registrado
--
-- Guarda um valor de width bits como metade baixa (o_lo, com os min(width, 32)
-- bits baixos) e metade alta (o_hi, com os width - 32 bits restantes, ausente
-- quando width não passa de 32). Os bits de cada saída acima da largura da
-- metade leem zero, e uma escrita guarda só os bits que cabem na metade.
-- A cada ciclo com i_inc = '1' a metade baixa soma 1; quando ela estava com
-- todos os bits em '1', o vai-um fica registrado e a metade alta soma 1 no
-- ciclo seguinte, de modo que nenhuma soma de 64 bits entra em um caminho
-- combinacional.
--
-- Leitura coerente: no ciclo em que o vai-um está pendente a metade alta
-- armazenada ainda não somou, então o_hi devolve a metade alta mais o vai-um
-- pendente. O par (o_hi, o_lo) é sempre o valor do contador de 64 bits ideal.
--
-- Prioridade da escrita sobre a soma, em cada metade:
--   1. i_we_lo = '1': a metade baixa recebe i_wdata e não há vai-um neste ciclo.
--   2. i_we_hi = '1': a metade alta recebe i_wdata e o vai-um pendente se perde.
--   3. Sem escrita: a metade baixa soma 1 com i_inc = '1' e a alta soma o vai-um.
--
-- Estouro (o_wrap): pulso de um ciclo quando uma soma leva o contador inteiro de todos os bits em '1' a zero, nunca
-- por uma escrita. Num contador que cabe na metade baixa o pulso sai registrado, um ciclo depois da soma. Num
-- contador com metade alta ele vale no ciclo em que o vai-um pendente leva a metade alta de todos os bits em '1'
-- a zero, sem uma escrita na metade alta no mesmo ciclo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;

entity counter64 is
	generic (
		-- Largura do contador em bits, de 1 a 64.
		width   : positive range 1 to 64 := 64
	);
	port (
		-- Sinal de clock do sistema.
		i_clk   : in  std_logic;
		-- Reset ativo em '1' (zera as duas metades e o vai-um).
		i_rst   : in  std_logic;
		-- Soma 1 ao contador neste ciclo quando '1'.
		i_inc   : in  std_logic;
		-- Escrita da metade baixa com i_wdata quando '1'.
		i_we_lo : in  std_logic;
		-- Escrita da metade alta com i_wdata quando '1'.
		i_we_hi : in  std_logic;
		-- Valor escrito na metade selecionada.
		i_wdata : in  word_t;
		-- Metade baixa do contador.
		o_lo    : out word_t;
		-- Metade alta do contador, já com o vai-um pendente somado.
		o_hi    : out word_t;
		-- Pulso de estouro: o contador de width bits passou de todos os bits em '1' para zero por uma soma.
		o_wrap  : out std_logic
	);
end entity counter64;

architecture rtl of counter64 is

	-- Largura da metade baixa: a do contador, até o máximo de 32 bits.
	function low_width return positive is
	begin
		if width > word_t'length then
			return word_t'length;
		end if;
		return width;
	end function;

	-- Largura de um sinal da metade alta, com 1 bit quando a metade não existe.
	function high_signal_width(w : natural) return positive is
	begin
		if w = 0 then
			return 1;
		end if;
		return w;
	end function;

	-- Largura da metade baixa.
	constant LO_WIDTH : positive := low_width;
	-- Largura da metade alta (0 quando o contador cabe na metade baixa).
	constant HI_WIDTH : natural := width - LO_WIDTH;
	-- Valor da metade baixa que gera o vai-um (todos os bits em '1').
	constant LO_ALL_ONES : std_logic_vector(LO_WIDTH - 1 downto 0) := (others => '1');

	-- Metade baixa armazenada.
	signal lo        : std_logic_vector(LO_WIDTH - 1 downto 0);
	-- Metade alta armazenada, sem o vai-um pendente.
	signal hi        : std_logic_vector(high_signal_width(HI_WIDTH) - 1 downto 0);
	-- A metade baixa passou do valor máximo no ciclo anterior e a alta ainda não somou.
	signal carry     : std_logic;
	-- Próximo valor da metade baixa.
	signal lo_nxt    : std_logic_vector(LO_WIDTH - 1 downto 0);
	-- Habilita a atualização da metade baixa.
	signal lo_en     : std_logic;
	-- Próximo valor da metade alta.
	signal hi_nxt    : std_logic_vector(high_signal_width(HI_WIDTH) - 1 downto 0);
	-- Habilita a atualização da metade alta.
	signal hi_en     : std_logic;
	-- Vai-um que a metade baixa gera neste ciclo.
	signal carry_nxt : std_logic;
	-- Metade baixa mais 1.
	signal lo_inc    : std_logic_vector(LO_WIDTH - 1 downto 0);
	-- Metade alta mais 1.
	signal hi_inc    : std_logic_vector(high_signal_width(HI_WIDTH) - 1 downto 0);
	-- Valor da metade alta que, somado ao vai-um pendente, estoura o contador (todos os bits em '1').
	signal hi_all_ones : std_logic;
	-- A soma deste ciclo estoura um contador que cabe na metade baixa.
	signal lo_wrap_nxt : std_logic;

begin

	lo_inc <= std_logic_vector(unsigned(lo) + 1);

	lo_nxt <= i_wdata(LO_WIDTH - 1 downto 0) when i_we_lo = '1' else lo_inc;
	lo_en  <= i_we_lo or i_inc;

	o_lo <= std_logic_vector(resize(unsigned(lo), word_t'length));

	u_lo : entity work.generic_register
		generic map (
			data_width => LO_WIDTH
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => lo_en,
			i_d      => lo_nxt,
			o_d      => lo
		);

	-- Contador que cabe na metade baixa: não há metade alta nem vai-um.
	gen_no_hi : if HI_WIDTH = 0 generate
		carry     <= '0';
		carry_nxt <= '0';
		hi_en     <= '0';
		hi_inc    <= (others => '0');
		hi_nxt    <= (others => '0');
		hi        <= (others => '0');
		o_hi      <= (others => '0');
		hi_all_ones <= '0';

		lo_wrap_nxt <= '1' when (i_inc = '1' and i_we_lo = '0' and lo = LO_ALL_ONES) else '0';

		u_wrap : entity work.flip_flop
			port map (
				i_d      => lo_wrap_nxt,
				o_d      => o_wrap,
				i_enable => '1',
				i_clk    => i_clk,
				i_rst    => i_rst
			);
	end generate gen_no_hi;

	gen_hi : if HI_WIDTH > 0 generate

		hi_inc <= std_logic_vector(unsigned(hi) + 1);

		hi_nxt <= i_wdata(HI_WIDTH - 1 downto 0) when i_we_hi = '1' else hi_inc;
		hi_en  <= i_we_hi or carry;

		carry_nxt <= '1' when (i_inc = '1' and i_we_lo = '0' and lo = LO_ALL_ONES) else '0';

		lo_wrap_nxt <= '0';
		hi_all_ones <= '1' when hi = (hi'range => '1') else '0';
		o_wrap      <= carry and hi_all_ones and (not i_we_hi);

		o_hi <= std_logic_vector(resize(unsigned(hi_inc), word_t'length)) when carry = '1' else
		        std_logic_vector(resize(unsigned(hi), word_t'length));

		u_hi : entity work.generic_register
			generic map (
				data_width => HI_WIDTH
			)
			port map (
				i_clk    => i_clk,
				i_rst    => i_rst,
				i_enable => hi_en,
				i_d      => hi_nxt,
				o_d      => hi
			);

		u_carry : entity work.flip_flop
			port map (
				i_d      => carry_nxt,
				o_d      => carry,
				i_enable => '1',
				i_clk    => i_clk,
				i_rst    => i_rst
			);

	end generate gen_hi;

end architecture rtl;
