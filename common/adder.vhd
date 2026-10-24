-- =============================================================================
-- Somador binário parametrizável sem sinal (unsigned)
--
-- Realiza combinacionalmente a soma aritmética de dois vetores de largura
-- configurável (data_width):
--   o_d = unsigned(i_d0) + unsigned(i_d1)
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
		-- Primeiro operando da soma.
		i_d0 : in  std_logic_vector((data_width-1) downto 0);
		-- Segundo operando da soma.
		i_d1 : in  std_logic_vector((data_width-1) downto 0);
		-- Resultado da soma (i_d0 + i_d1).
		o_d  : out std_logic_vector((data_width-1) downto 0)
	);

end entity;

architecture rtl of adder is
begin

	o_d <= std_logic_vector(unsigned(i_d0) + unsigned(i_d1));

end architecture;
