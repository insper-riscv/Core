-- =============================================================================
-- Divisor de clock que gera um pulso de tick a cada tick_cycles ciclos
--
-- Conta de 0 a tick_cycles - 1 e emite o_tick = '1' no ciclo em que a contagem
-- chega ao fim, voltando a 0 no ciclo seguinte. Com o clock do core em 50 MHz e
-- tick_cycles = 50, o tick é de 1 MHz. Um reset zera a contagem.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tick_divider is
	generic (
		-- Número de ciclos de clock entre dois ticks (no mínimo 1).
		tick_cycles : positive := 50
	);
	port (
		-- Sinal de clock do sistema.
		i_clk  : in  std_logic;
		-- Reset síncrono ativo em '1'.
		i_rst  : in  std_logic;
		-- Pulso de um ciclo a cada tick_cycles ciclos de clock.
		o_tick : out std_logic
	);
end entity tick_divider;

architecture rtl of tick_divider is

	-- Ciclos já contados desde o último tick.
	signal count : natural range 0 to tick_cycles - 1 := 0;
	-- A contagem chegou ao fim neste ciclo.
	signal last  : std_logic;

begin

	last   <= '1' when count = tick_cycles - 1 else '0';
	o_tick <= last;

	process (i_clk)
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' or last = '1' then
				count <= 0;
			else
				count <= count + 1;
			end if;
		end if;
	end process;

end architecture rtl;
