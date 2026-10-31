-- =============================================================================
-- Constantes do mapa de memória do processador RV32
--
-- Centraliza os limites de endereço das regiões de memória de instruções e de
-- dados (BOOT_ROM, FLASH, RAM interna e janela externa de SDRAM/periféricos).
-- As fronteiras das regiões são potências de 2: cada *_BIT é o índice do único
-- bit em '1' do endereço base correspondente, e a região sai de testes desse
-- bit no endereço, sem comparador numérico.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mem_map_consts is

	-- Tamanho em bytes da janela de endereços da BOOT_ROM (0x00000000 .. 0x000007FF, 2 KiB).
	constant BOOT_ROM_SIZE_BYTES   : unsigned(31 downto 0) := to_unsigned(16#00000800#, 32);

	-- Índice do bit do endereço base da memória RAM interna de dados (2**15 = 0x00008000).
	constant RAM_BASE_BIT          : natural := 15;
	-- Índice do bit do endereço base da FLASH externa no mapa da plataforma sdram (2**29 = 0x20000000).
	constant FLASH_EXT_BASE_BIT    : natural := 29;
	-- Índice do bit do endereço base da janela externa de SDRAM e periféricos (2**30 = 0x40000000).
	constant SDRAM_BASE_BIT        : natural := 30;
	-- Índice do bit do endereço base da janela de periféricos dentro da janela externa (2**31 = 0x80000000).
	constant PERIPHERAL_BASE_BIT   : natural := 31;

	-- Endereço base em bytes da memória RAM interna de dados (0x00008000).
	constant RAM_BASE_BYTES        : unsigned(31 downto 0) := shift_left(to_unsigned(1, 32), RAM_BASE_BIT);

	-- Endereço base em bytes da janela externa de SDRAM e periféricos (0x40000000).
	constant SDRAM_BASE_BYTES      : unsigned(31 downto 0) := shift_left(to_unsigned(1, 32), SDRAM_BASE_BIT);

	-- Endereço base em bytes da FLASH externa no mapa da plataforma sdram (0x20000000, bit 29 = 1).
	constant FLASH_EXT_BASE_BYTES  : unsigned(31 downto 0) := shift_left(to_unsigned(1, 32), FLASH_EXT_BASE_BIT);

	-- Endereço base em bytes da janela de periféricos dentro da janela externa (0x80000000, bit 31 = 1).
	constant PERIPHERAL_BASE_BYTES : unsigned(31 downto 0) := shift_left(to_unsigned(1, 32), PERIPHERAL_BASE_BIT);

end package mem_map_consts;
