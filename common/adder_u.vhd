-- =============================================================================
-- Somador binário parametrizável com extensão mista (signed + unsigned)
--
-- Realiza combinacionalmente a soma entre o primeiro operando interpretado
-- com sinal (signed) e o segundo operando interpretado sem sinal (unsigned),
-- mantendo a largura configurável (data_width):
--   o_d = signed(i_d0) + signed(resize(unsigned(i_d1), data_width))
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
		-- Primeiro operando (tratado com sinal).
		i_d0 : in  std_logic_vector((data_width-1) downto 0);
		-- Segundo operando (tratado sem sinal).
		i_d1 : in  std_logic_vector((data_width-1) downto 0);
		-- Resultado da soma mista signed(i_d0) + unsigned(i_d1).
		o_d  : out std_logic_vector((data_width-1) downto 0)
	);

end entity;

architecture rtl of adder_u is
begin

	o_d <= std_logic_vector(signed(i_d0) + signed(resize(unsigned(i_d1), data_width)));

end architecture;
