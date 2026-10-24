-- =============================================================================
-- Somador binário parametrizável sem sinal (unsigned)
--
-- Realiza combinacionalmente a soma aritmética de dois operandos de largura
-- configurável (data_width):
--   o_d = unsigned(i_a) + unsigned(i_b)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder is

	generic (
		-- Largura dos operandos e da saída (em bits).
		data_width : natural := 32
	);

	port (
		-- Operando A da soma.
		i_a : in  std_logic_vector((data_width-1) downto 0);
		-- Operando B da soma.
		i_b : in  std_logic_vector((data_width-1) downto 0);
		-- Resultado da soma (i_a + i_b).
		o_d : out std_logic_vector((data_width-1) downto 0)
	);

end entity;

architecture rtl of adder is
begin

	o_d <= std_logic_vector(unsigned(i_a) + unsigned(i_b));

end architecture;
