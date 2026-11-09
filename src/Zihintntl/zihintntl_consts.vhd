-- =============================================================================
-- Constantes de codificação da extensão Zihintntl (Non-Temporal Locality Hints)
--
-- As quatro dicas de 32 bits são ADDs com rd = x0 e rs1 = x0, e o registrador
-- rs2 escolhe o domínio de localidade: x2 (ntl.p1), x3 (ntl.pall), x4 (ntl.s1)
-- e x5 (ntl.all). Escrever em x0 é descartado, então a dica é um nop.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package zihintntl_consts is

    -- Índice do primeiro registrador rs2 que codifica uma dica (ntl.p1, x2).
    constant ZIHINTNTL_RS2_FIRST : std_logic_vector(4 downto 0) := "00010";
    -- Índice do último registrador rs2 que codifica uma dica (ntl.all, x5).
    constant ZIHINTNTL_RS2_LAST  : std_logic_vector(4 downto 0) := "00101";
    -- Índice de rd e de rs1 nas quatro dicas (x0).
    constant ZIHINTNTL_REG_ZERO  : std_logic_vector(4 downto 0) := "00000";

end package zihintntl_consts;
