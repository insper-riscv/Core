-- =============================================================================
-- Somador binário parametrizável com extensão mista (signed + unsigned)
--
-- Realiza combinacionalmente a soma entre o operando A interpretado com sinal
-- (signed) e o operando B interpretado sem sinal (unsigned), mantendo a largura
-- configurável (data_width):
--   o_d = signed(i_a) + signed(resize(unsigned(i_b), data_width))
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder_u is

	generic (
		-- Largura dos operandos e da saída (em bits).
		data_width : natural := 32
	);

	port (
		-- Operando A (interpretado com sinal).
		i_a : in  std_logic_vector((data_width-1) downto 0);
		-- Operando B (interpretado sem sinal).
		i_b : in  std_logic_vector((data_width-1) downto 0);
		-- Resultado da soma mista signed(i_a) + unsigned(i_b).
		o_d : out std_logic_vector((data_width-1) downto 0)
	);

end entity;

architecture rtl of adder_u is
begin

	o_d <= std_logic_vector(signed(i_a) + signed(resize(unsigned(i_b), data_width)));

end architecture;
