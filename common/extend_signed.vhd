-- =============================================================================
-- Extensor de sinal de 1 bit para dois operandos (suporte à extensão M)
--
-- Estende dois operandos (i_a e i_b) de largura data_width para (data_width + 1)
-- bits, permitindo utilizar um único multiplicador com sinal para operações
-- signed x signed (MULH), signed x unsigned (MULHSU) e unsigned x unsigned
-- (MULHU).
--
-- Codificação de i_signed:
--   "11" -> o_a e o_b estendidos com sinal (MSB replicado)
--   "10" -> o_a estendido com sinal e o_b estendido com zero
--   "00" (ou "01") -> o_a e o_b estendidos com zero
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity extend_signed is

	generic (
		-- Largura dos operandos de entrada (em bits).
		data_width : natural := 32
	);

	port (
		-- Operando A de entrada (data_width bits).
		i_a      : in  std_logic_vector((data_width-1) downto 0);
		-- Operando B de entrada (data_width bits).
		i_b      : in  std_logic_vector((data_width-1) downto 0);
		-- Modo de extensão de sinal ("11" = ambos signed, "10" = apenas i_a signed, "00" = ambos unsigned).
		i_signed : in  std_logic_vector(1 downto 0);
		-- Operando A estendido em 1 bit (data_width + 1 bits).
		o_a      : out std_logic_vector(data_width downto 0);
		-- Operando B estendido em 1 bit (data_width + 1 bits).
		o_b      : out std_logic_vector(data_width downto 0)
	);

end entity extend_signed;

architecture rtl of extend_signed is
begin

	-- O ramo final sem condição evita inferência de latch para a combinação não utilizada "01".
	o_a <= i_a(data_width-1) & i_a when i_signed = "11" else
	       i_a(data_width-1) & i_a when i_signed = "10" else
	       '0' & i_a;

	o_b <= i_b(data_width-1) & i_b when i_signed = "11" else
	       '0' & i_b               when i_signed = "10" else
	       '0' & i_b;

end architecture rtl;
