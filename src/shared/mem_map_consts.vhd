-- =============================================================================
-- Funções do mapa de memória do processador RV32
--
-- O mapa é recebido pelo núcleo por genéricos de elaboração, e este pacote
-- reúne as conversões de que os pontos de decodificação precisam (BOOT_ROM,
-- ROM interna, janela externa e janela de periféricos). Cada projeto fixa os
-- limites no `config.yml` da sua plataforma.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mem_map_consts is

	-- Converte um endereço dado em KiB para o endereço em bytes de 32 bits.
	function kib_to_addr(arg : natural) return unsigned;

	-- Endereço exclusivo do fim da BOOT_ROM, que ocupa [0, 2**bits).
	function boot_rom_end(bits : natural) return unsigned;

	-- Endereço exclusivo do fim da ROM interna, ou zero quando a ROM é externa.
	function internal_rom_end(end_kib : natural; external : boolean) return unsigned;

	-- Início da memória principal: logo depois da ROM interna, ou a base externa quando a ROM é externa.
	function main_mem_base(end_kib : natural; ext_kib : natural; external : boolean) return unsigned;

end package mem_map_consts;

package body mem_map_consts is

	function kib_to_addr(arg : natural) return unsigned is
	begin
		return shift_left(to_unsigned(arg, 32), 10);
	end function kib_to_addr;

	function boot_rom_end(bits : natural) return unsigned is
	begin
		return shift_left(to_unsigned(1, 32), bits);
	end function boot_rom_end;

	function internal_rom_end(end_kib : natural; external : boolean) return unsigned is
	begin
		if external then
			return to_unsigned(0, 32);
		end if;
		return kib_to_addr(end_kib);
	end function internal_rom_end;

	function main_mem_base(end_kib : natural; ext_kib : natural; external : boolean) return unsigned is
	begin
		if external then
			return kib_to_addr(ext_kib);
		end if;
		return kib_to_addr(end_kib);
	end function main_mem_base;

end package body mem_map_consts;
