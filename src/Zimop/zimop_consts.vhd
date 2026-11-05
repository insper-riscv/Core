-- =============================================================================
-- Constantes de codificação da extensão Zimop (May-Be-Operations)
--
-- As 40 instruções ocupam a classe SYSTEM com funct3 = FUNCT3_SYSTEM_RESERVED.
-- mop.r.n (n = 0 a 31) tem o bit 31 em 1, os bits [29:28] e o bit 25 em zero e
-- os bits [24:22] em um; n[4] está no bit 30, n[3:2] nos bits [27:26] e n[1:0]
-- nos bits [21:20]. mop.rr.n (n = 0 a 7) tem o bit 31 em 1, os bits [29:28] em
-- zero e o bit 25 em 1; n[2] está no bit 30 e n[1:0] nos bits [27:26].
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package zimop_consts is

	-- Valor fixo do bit 31 das 40 instruções.
	constant ZIMOP_BIT31       : std_logic := '1';
	-- Valor fixo dos bits [29:28] das 40 instruções.
	constant ZIMOP_BITS_29_28  : std_logic_vector(1 downto 0) := "00";
	-- Valor do bit 25 que distingue mop.r.n ('0') de mop.rr.n ('1').
	constant ZIMOP_BIT25_R     : std_logic := '0';
	-- Valor do bit 25 de mop.rr.n.
	constant ZIMOP_BIT25_RR    : std_logic := '1';
	-- Valor fixo dos bits [24:22] de mop.r.n.
	constant ZIMOP_BITS_24_22  : std_logic_vector(2 downto 0) := "111";

end package zimop_consts;
