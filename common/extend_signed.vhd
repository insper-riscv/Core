-- =============================================================================
-- Extensor de sinal de 1 bit para dois operandos (suporte à extensão M)
--
-- Estende dois operandos de largura data_width para (data_width + 1) bits,
-- permitindo utilizar um único multiplicador com sinal para operações signed x
-- signed (MULH), signed x unsigned (MULHSU) e unsigned x unsigned (MULHU).
--
-- Codificação de i_signed:
--   "11" -> o_d0 e o_d1 estendidos com sinal (MSB replicado)
--   "10" -> o_d0 estendido com sinal e o_d1 estendido com zero
--   "00" (ou "01") -> o_d0 e o_d1 estendidos com zero
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
		-- Primeiro operando de entrada (data_width bits).
		i_d0     : in  std_logic_vector((data_width-1) downto 0);
		-- Segundo operando de entrada (data_width bits).
		i_d1     : in  std_logic_vector((data_width-1) downto 0);
		-- Modo de extensão de sinal ("11" = ambos signed, "10" = apenas i_d0 signed, "00" = ambos unsigned).
		i_signed : in  std_logic_vector(1 downto 0);
		-- Primeiro operando estendido em 1 bit (data_width + 1 bits).
		o_d0     : out std_logic_vector(data_width downto 0);
		-- Segundo operando estendido em 1 bit (data_width + 1 bits).
		o_d1     : out std_logic_vector(data_width downto 0)
	);

end entity extend_signed;

architecture rtl of extend_signed is
begin

	-- O ramo final sem condição evita inferência de latch para a combinação não utilizada "01".
	o_d0 <= i_d0(data_width-1) & i_d0 when i_signed = "11" else
	        i_d0(data_width-1) & i_d0 when i_signed = "10" else
	        '0' & i_d0;

	o_d1 <= i_d1(data_width-1) & i_d1 when i_signed = "11" else
	        '0' & i_d1                when i_signed = "10" else
	        '0' & i_d1;

end architecture rtl;
