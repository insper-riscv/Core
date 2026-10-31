-- =============================================================================
-- Constantes de modo de sinal da multiplicação e divisão
--
-- Código de 2 bits que o multdiv deriva do funct3 registrado para dizer ao
-- multiplicador de Booth e ao divisor quais operandos têm sinal.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package muldiv_consts is

	-- Modo de sinal dos operandos: bit 1 para o operando A e bit 0 para o operando B ('1' = com sinal).
	subtype signed_mode_t is std_logic_vector(1 downto 0);

	-- Nenhum operando tem sinal (MULHU, DIVU e REMU).
	constant SIGNED_NONE   : signed_mode_t := "00";
	-- Somente o operando A tem sinal (MULHSU).
	constant SIGNED_A_ONLY : signed_mode_t := "10";
	-- Ambos os operandos têm sinal (MUL, MULH, DIV e REM).
	constant SIGNED_BOTH   : signed_mode_t := "11";

end package muldiv_consts;
