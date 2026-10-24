library ieee;
use ieee.std_logic_1164.all;

entity mux_2x1 is
	
	generic (
		-- Largura dos barramentos de dados (em bits).
		data_width : natural := 8
	);
	
	port (
		-- Entrada de dados 0 (selecionada quando i_sel = '0').
		i_d0  : in  std_logic_vector((data_width-1) downto 0);
		-- Entrada de dados 1 (selecionada quando i_sel = '1').
		i_d1  : in  std_logic_vector((data_width-1) downto 0);
		-- Sinal seletor do multiplexador.
		i_sel : in  std_logic;
		-- Saída de dados selecionada.
		o_d   : out std_logic_vector((data_width-1) downto 0)
	);
  
end entity;

architecture rtl of mux_2x1 is

begin

o_d <= i_d1 when (i_sel = '1') else 
	   i_d0;

end architecture;
