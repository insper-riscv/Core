-- =============================================================================
-- Flip-Flop tipo D de 1 bit com habilitação e reset assíncrono
--
-- Armazena um bit de estado na borda de subida de i_clk quando i_enable = '1'.
--
-- Quando i_rst = '1' (assíncrono): o_d = '0'
-- Quando i_rst = '0' e borda de subida de i_clk:
--   - i_enable = '1': o_d recebe i_d
--   - i_enable = '0': o_d mantém o valor anterior
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity flip_flop is

	port (
		-- Bit de entrada a ser armazenado na borda de subida do clock.
		i_d      : in  std_logic := '0';
		-- Bit armazenado no flip-flop.
		o_d      : out std_logic := '0';
		-- Habilita a atualização do flip-flop quando '1'.
		i_enable : in  std_logic := '0';
		-- Sinal de clock.
		i_clk    : in  std_logic;
		-- Sinal de reset assíncrono ativo em '1'.
		i_rst    : in  std_logic := '1'
	);

end entity;

architecture rtl of flip_flop is
begin
	process(i_rst, i_clk)
	begin
		if (i_rst = '1') then
			o_d <= '0';
		else
			if (rising_edge(i_clk)) then
				if (i_enable = '1') then
					o_d <= i_d;
				end if;
			end if;
		end if;
	end process;
end architecture;
