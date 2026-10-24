-- =============================================================================
-- Pacote de tipos e funções utilitárias de hardware
--
-- Define o tipo de matriz de palavras (word_array_t) compatível com VHDL-2008
-- e funções auxiliares combinacionais para comparação de vetores (equals,
-- not_equals) e cálculo de largura de endereço em tempo de elaboração
-- (log2_ceil).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package utils_pkg is

  -- Elemento de palavra de largura não-constrangida.
  subtype word_t is std_logic_vector;
  -- Matriz não-constrangida de palavras de dados.
  type    word_array_t is array (natural range <>) of word_t;

  -- Retorna '1' quando os vetores a e b são bit a bit iguais, e '0' caso contrário.
  function equals(a : in std_logic_vector; b : in std_logic_vector) return std_logic;

  -- Retorna '1' quando os vetores a e b diferem em pelo menos um bit, e '0' caso contrário.
  function not_equals(a : in std_logic_vector; b : in std_logic_vector) return std_logic;

  -- Calcula o menor inteiro natural n tal que 2^n >= arg.
  function log2_ceil(arg : positive) return natural;

end package;

package body utils_pkg is 

function equals(a : in std_logic_vector; b : in std_logic_vector) return std_logic is

	alias av : std_logic_vector(a'length - 1 downto 0) is a;
	alias bv : std_logic_vector(b'length - 1 downto 0) is b;

	-- Variavel para o resultado acumulado do AND
	variable result : std_logic := '1';

	begin
	-- 1. Realiza a comparacao bit a bit usando XNOR	  
	-- 2. Combina os resultados com uma operacao AND
		for i in av'range loop

			result := result and (av(i) xnor bv(i));

		end loop;

	return result;

end function equals;

function not_equals(a : in std_logic_vector; b : in std_logic_vector) return std_logic is

	alias av : std_logic_vector(a'length - 1 downto 0) is a;
	alias bv : std_logic_vector(b'length - 1 downto 0) is b;

	-- Variavel para o resultado acumulado do OR
	variable result : std_logic := '0';

	begin
	-- 1. Realiza a comparacao bit a bit usando XOR	  
	-- 2. Combina os resultados com uma operacao OR
		for i in av'range loop

			result := result or (av(i) xor bv(i));

		end loop;

	return result;

end function not_equals;

function log2_ceil(arg : positive) return natural is
	
	variable result : natural := 0;
	
	begin
	
		while (2**result) < arg loop
		
			result := result + 1;
			
		end loop;
		
	return result;
	
end function log2_ceil;

end package body;