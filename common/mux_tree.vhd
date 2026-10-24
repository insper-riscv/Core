library ieee;
use ieee.std_logic_1164.all;
use work.utils_pkg.all;

entity mux_tree is
	
	generic (
		-- Largura de cada palavra de dados (em bits).
		data_width     : natural := 8;
		-- Largura do seletor binário (2^selector_width palavras de entrada).
		selector_width : natural := 5
	);
	
	port (
		-- Matriz de palavras de entrada.
		i_array : in  word_array_t(((2**selector_width)-1) downto 0)((data_width-1) downto 0);
		-- Índice binário da palavra selecionada.
		i_sel   : in  std_logic_vector((selector_width-1) downto 0);
		-- Palavra selecionada na saída da árvore de multiplexadores.
		o_d     : out std_logic_vector((data_width-1) downto 0)
	);
	
end entity;

architecture rtl of mux_tree is

-- Tipo de array para os estagios intermediarios da arvore de muxes
type mux_tree_t is array (selector_width downto 0) of word_array_t(((2**selector_width)-1) downto 0)((data_width-1) downto 0);
  
-- Sinais para cada estagio da arvore de muxes
signal mux_levels : mux_tree_t;


begin

mux_levels(0) <= i_array;

-- Gera os estagios da arvore de muxes
gen_mux_tree : for i in 0 to (selector_width-1) generate
	
	-- Gera os multiplexadores para o estágio 'i' da árvore.
	gen_muxes : for j in 0 to (((2**selector_width) / (2**(i+1))) - 1) generate
		
		-- A lógica (j*2) e (j*2 + 1) garante que cada MUX do estágio
		-- seguinte selecione entre dois sinais adjacentes do estágio anterior,
		mux_levels(i+1)(j) <= mux_levels(i)(j*2 + 1) when i_sel(i) = '1' else mux_levels(i)(j*2);
		
	end generate;
	
end generate;

-- A saida e o resultado do ultimo estagio
o_d <= mux_levels(selector_width)(0);

end architecture;