-- =============================================================================
-- Multiplexador 4x1 parametrizável
--
-- Seleciona combinacionalmente entre quatro barramentos de entrada de largura
-- configurável (data_width) de acordo com o seletor de 2 bits i_sel.
--
-- Quando i_sel = "00": o_d = i_d0
-- Quando i_sel = "01": o_d = i_d1
-- Quando i_sel = "10": o_d = i_d2
-- Quando i_sel = "11": o_d = i_d3
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity mux_4x1 is

	generic (
		-- Largura dos barramentos de dados (em bits).
		data_width : natural := 8
	);

	port (
		-- Entrada de dados 0 (selecionada quando i_sel = "00").
		i_d0  : in  std_logic_vector((data_width-1) downto 0);
		-- Entrada de dados 1 (selecionada quando i_sel = "01").
		i_d1  : in  std_logic_vector((data_width-1) downto 0);
		-- Entrada de dados 2 (selecionada quando i_sel = "10").
		i_d2  : in  std_logic_vector((data_width-1) downto 0);
		-- Entrada de dados 3 (selecionada quando i_sel = "11").
		i_d3  : in  std_logic_vector((data_width-1) downto 0);
		-- Sinal seletor de 2 bits do multiplexador.
		i_sel : in  std_logic_vector(1 downto 0);
		-- Saída de dados selecionada.
		o_d   : out std_logic_vector((data_width-1) downto 0)
	);

end entity;

architecture rtl of mux_4x1 is

begin

	with i_sel select
		o_d <= i_d0 when "00",
		       i_d1 when "01",
		       i_d2 when "10",
		       i_d3 when others;

end architecture;
