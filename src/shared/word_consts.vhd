-- =============================================================================
-- Constantes de valor da palavra de 32 bits do processador RV32
--
-- Centraliza os valores de palavra usados na lógica dos estágios e das
-- extensões: o passo sequencial do Program Counter e os dois valores especiais do resultado da divisão (divisão por zero e estouro).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package word_consts is

	-- Palavra com todos os bits em '1' (-1 em complemento de dois, 0xFFFFFFFF).
	constant WORD_ALL_ONES : word_t := x"FFFFFFFF";

	-- Menor inteiro negativo representável em 32 bits com sinal (-2^31, 0x80000000).
	constant WORD_INT_MIN : word_t := x"80000000";

	-- Incremento sequencial do Program Counter: 4 bytes por instrução de 32 bits.
	constant INSTR_BYTES : word_t := x"00000004";

end package word_consts;
