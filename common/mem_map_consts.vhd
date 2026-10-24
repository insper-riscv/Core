-- =============================================================================
-- Constantes do mapa de memória do processador RV32
--
-- Centraliza os limites de endereço das regiões de memória de instruções e de
-- dados (BOOT_ROM, FLASH, RAM interna e janela externa de SDRAM/periféricos).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mem_map_consts is

	-- Tamanho em bytes da janela de endereços da BOOT_ROM (0x00000000 .. 0x000007FF, 2 KiB).
	constant BOOT_ROM_SIZE_BYTES : unsigned(31 downto 0) := to_unsigned(16#00000800#, 32);

	-- Endereço base em bytes da memória RAM interna de dados (0x00008000).
	constant RAM_BASE_BYTES      : unsigned(31 downto 0) := to_unsigned(16#00008000#, 32);

	-- Endereço base em bytes da janela externa de SDRAM e periféricos (0x40000000).
	constant SDRAM_BASE_BYTES    : unsigned(31 downto 0) := to_unsigned(16#40000000#, 32);

end package mem_map_consts;
