-- =============================================================================
-- Constantes de máscara de bytes e de posição do byte dentro da palavra
--
-- Máscaras de habilitação de bytes (byte_mask_t, um bit por byte, bit 0 = byte
-- menos significativo) dos stores e posições do primeiro byte de um acesso na
-- palavra de 32 bits (os dois bits menos significativos do endereço efetivo).
-- Usadas pelo store_manager, pela misaligned_unit e pela unidade de traps no
-- lugar de literais binários soltos.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package byte_mask_consts is

	-- Largura de um byte (em bits).
	constant BYTE_WIDTH : natural := 8;

	-- Posição do primeiro byte de um acesso dentro da palavra (endereço efetivo [1:0]).
	subtype byte_offset_t is std_logic_vector(1 downto 0);

	-- Primeiro byte no byte 0 da palavra (acesso alinhado à palavra).
	constant BYTE_OFFSET_0 : byte_offset_t := "00";
	-- Primeiro byte no byte 1 da palavra.
	constant BYTE_OFFSET_1 : byte_offset_t := "01";
	-- Primeiro byte no byte 2 da palavra.
	constant BYTE_OFFSET_2 : byte_offset_t := "10";
	-- Primeiro byte no byte 3 da palavra (um acesso de meia palavra ou de palavra cruza para a palavra seguinte).
	constant BYTE_OFFSET_3 : byte_offset_t := "11";

	-- Nenhum byte habilitado (loads e instruções que não escrevem na memória).
	constant BYTE_MASK_NONE      : byte_mask_t := "0000";
	-- Somente o byte 0 (SB no offset 0).
	constant BYTE_MASK_BYTE_0    : byte_mask_t := "0001";
	-- Somente o byte 1 (SB no offset 1).
	constant BYTE_MASK_BYTE_1    : byte_mask_t := "0010";
	-- Somente o byte 2 (SB no offset 2).
	constant BYTE_MASK_BYTE_2    : byte_mask_t := "0100";
	-- Somente o byte 3 (SB no offset 3).
	constant BYTE_MASK_BYTE_3    : byte_mask_t := "1000";
	-- Meia palavra nos bytes 0 e 1 (SH no offset 0).
	constant BYTE_MASK_HALF_LOW  : byte_mask_t := "0011";
	-- Meia palavra nos bytes 1 e 2 (SH no offset 1, dentro da palavra).
	constant BYTE_MASK_HALF_MID  : byte_mask_t := "0110";
	-- Meia palavra nos bytes 2 e 3 (SH no offset 2 e, cruzando a palavra, no offset 3).
	constant BYTE_MASK_HALF_HIGH : byte_mask_t := "1100";
	-- Palavra inteira (SW).
	constant BYTE_MASK_WORD      : byte_mask_t := "1111";

end package byte_mask_consts;
