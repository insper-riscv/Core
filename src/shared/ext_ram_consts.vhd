-- =============================================================================
-- Constantes de modo do extensor da memória de dados (ext_ram_op_t)
--
-- Define os códigos de 3 bits (EXT_RAM_*) que selecionam a largura (palavra,
-- meia-palavra ou byte) e o tipo de extensão (sinal ou zero) nos loads, e a
-- função que diz se um acesso cruza o limite da palavra.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.byte_mask_consts.all;

package ext_ram_consts is

    -- Leitura de palavra completa de 32 bits (LW).
    constant EXT_RAM_LW  : ext_ram_op_t := "000";
    -- Leitura de meia-palavra de 16 bits com extensão de sinal (LH).
    constant EXT_RAM_LH  : ext_ram_op_t := "001";
    -- Leitura de meia-palavra de 16 bits com extensão por zero (LHU).
    constant EXT_RAM_LHU : ext_ram_op_t := "010";
    -- Leitura de byte de 8 bits com extensão de sinal (LB).
    constant EXT_RAM_LB  : ext_ram_op_t := "011";
    -- Leitura de byte de 8 bits com extensão por zero (LBU).
    constant EXT_RAM_LBU : ext_ram_op_t := "100";

    -- Diz se o load ou o store ocupa duas palavras da memória: LW fora do byte 0 e LH ou LHU no byte 3 (loads, pelo
    -- modo de extensão), SW fora do byte 0 e SH no byte 3 (stores, pela máscara de bytes que saiu do store_manager).
    function is_cross_access (
        re      : std_logic;
        we      : std_logic;
        ext_op  : ext_ram_op_t;
        mask    : byte_mask_t;
        offset  : byte_offset_t
    ) return std_logic;

end package ext_ram_consts;

package body ext_ram_consts is

    function is_cross_access (
        re      : std_logic;
        we      : std_logic;
        ext_op  : ext_ram_op_t;
        mask    : byte_mask_t;
        offset  : byte_offset_t
    ) return std_logic is
    begin

        if re = '1' and
           ((ext_op = EXT_RAM_LW and offset /= BYTE_OFFSET_0) or
            ((ext_op = EXT_RAM_LH or ext_op = EXT_RAM_LHU) and offset = BYTE_OFFSET_3)) then
            return '1';
        end if;

        if we = '1' and
           ((mask = BYTE_MASK_WORD and offset /= BYTE_OFFSET_0) or
            (mask = BYTE_MASK_HALF_HIGH and offset = BYTE_OFFSET_3)) then
            return '1';
        end if;

        return '0';

    end function is_cross_access;

end package body ext_ram_consts;
