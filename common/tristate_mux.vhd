-- =============================================================================
-- Multiplexador parametrizável baseado em buffers tri-state
--
-- Decodifica o seletor binário i_sel em um vetor one-hot via onehot_decoder
-- e habilita apenas a palavra correspondente de i_array no barramento de
-- saída o_d, mantendo as demais em alta impedância ('Z').
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.utils_pkg.all;

entity tristate_mux is
	
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
		-- Palavra selecionada no barramento tri-state de saída.
		o_d     : out std_logic_vector((data_width-1) downto 0)
	);
	
end entity;

architecture rtl of tristate_mux is

-- Vetor one-hot que habilita apenas um buffer tri-state por vez.
signal decoded_selector : std_logic_vector(((2**selector_width)-1) downto 0);


begin

-- Decodifica o Seletor
read_decoder : entity work.onehot_decoder

generic map (
	num_inputs => selector_width
)

port map (
	i_d => i_sel,
	o_d => decoded_selector
);

gen_inputs : for i in 0 to ((2**selector_width) - 1) generate begin
	
	o_d <= i_array(i) when decoded_selector(i) = '1' else (others => 'Z');
	
end generate;
  
end architecture;