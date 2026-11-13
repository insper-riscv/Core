-- =============================================================================
-- Constantes de valor da palavra de XLEN bits do processador
--
-- Centraliza os valores de palavra usados na lógica dos estágios e das
-- extensões: o passo sequencial do Program Counter e os dois valores especiais do resultado da divisão (divisão por
-- zero e estouro).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;

package word_consts is

    -- Palavra com todos os bits em '1' (-1 em complemento de dois).
    constant WORD_ALL_ONES : word_t := (others => '1');

    -- Menor inteiro negativo representável em XLEN bits com sinal (-2^(XLEN-1)): só o bit mais significativo em '1'.
    constant WORD_INT_MIN : word_t := std_logic_vector(shift_left(to_unsigned(1, XLEN), XLEN - 1));

    -- Incremento sequencial do Program Counter: 4 bytes por instrução de 32 bits.
    constant INSTR_BYTES : word_t := std_logic_vector(to_unsigned(4, XLEN));

end package word_consts;
