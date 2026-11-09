-- =============================================================================
-- Constantes de codificação da extensão Zihintpause
--
-- A instrução pause é um FENCE com fm = 0000, pred = 0001 (W), succ = 0000,
-- rs1 = x0 e rd = x0, ou seja, a palavra 0x0100000F.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package zihintpause_consts is

    -- Campos [31:20] de pause: fm = 0000, pred = 0001 e succ = 0000.
    constant ZIHINTPAUSE_FM_PRED_SUCC : std_logic_vector(11 downto 0) := "000000010000";
    -- Índice de rd e de rs1 em pause (x0).
    constant ZIHINTPAUSE_REG_ZERO     : std_logic_vector(4 downto 0)  := "00000";

end package zihintpause_consts;
