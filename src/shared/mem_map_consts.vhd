-- =============================================================================
-- Funções do mapa de memória do processador RV32
--
-- O mapa é recebido pelo núcleo por genéricos de elaboração, e este pacote
-- reúne as conversões de que os pontos de decodificação precisam (BOOT_MEMORY,
-- ROM interna, janela externa e janela de periféricos). Cada projeto fixa os
-- limites no `platform.yaml` da sua plataforma.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mem_map_consts is

	-- Converte um endereço dado em KiB para o endereço em bytes de 32 bits.
	function kib_to_addr(arg : natural) return unsigned;

	-- Endereço exclusivo do fim da BOOT_MEMORY, que ocupa [0, 2**bits).
	function boot_memory_end(bits : natural) return unsigned;

	-- Endereço exclusivo do fim da ROM interna, ou zero quando a ROM é externa.
	function internal_rom_end(end_kib : natural; external : boolean) return unsigned;

	-- Início da memória principal: logo depois da ROM interna; com a ROM externa, a base externa quando a ROM é vazia
	-- ou o fim da BOOT_MEMORY, pois a ROM externa, que começa ali, é lida e escrita pela porta externa como a RAM.
	function main_mem_base(end_kib : natural; ext_kib : natural; external : boolean; boot_bits : natural) return unsigned;

	-- O endereço sai pela porta externa: a janela externa, a ROM quando é externa ou a RAM quando é externa.
	function is_external_addr(
		addr         : unsigned;
		rom_end_kib  : natural;
		rom_external : boolean;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ram_external : boolean;
		ext_base_kib : natural
	) return boolean;

	-- A palavra do endereço é a última de uma região: a seguinte pertenceria à região vizinha.
	function is_last_word(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural
	) return boolean;

	-- O endereço está no intervalo de leitura válido do mapa: ROM, RAM, janela externa ou um slot de periférico ocupado.
	function addr_readable(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural;
		periph_slots : std_logic_vector(7 downto 0)
	) return boolean;

	-- O endereço aceita escrita: o mapa válido sem a ROM (BOOT_MEMORY e FLASH são só de leitura).
	function addr_writable(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural;
		periph_slots : std_logic_vector(7 downto 0)
	) return boolean;

	-- O endereço aceita busca de instrução: ROM, RAM e janela externa (nunca periférico).
	function addr_executable(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural
	) return boolean;

end package mem_map_consts;

package body mem_map_consts is

	function kib_to_addr(arg : natural) return unsigned is
	begin
		return shift_left(to_unsigned(arg, 32), 10);
	end function kib_to_addr;

	function boot_memory_end(bits : natural) return unsigned is
	begin
		return shift_left(to_unsigned(1, 32), bits);
	end function boot_memory_end;

	function internal_rom_end(end_kib : natural; external : boolean) return unsigned is
	begin
		if external then
			return to_unsigned(0, 32);
		end if;
		return kib_to_addr(end_kib);
	end function internal_rom_end;

	function main_mem_base(end_kib : natural; ext_kib : natural; external : boolean; boot_bits : natural) return unsigned is
	begin
		if external and end_kib = 0 then
			return kib_to_addr(ext_kib);
		end if;
		if external then
			return boot_memory_end(boot_bits);
		end if;
		return kib_to_addr(end_kib);
	end function main_mem_base;

	function is_external_addr(
		addr         : unsigned;
		rom_end_kib  : natural;
		rom_external : boolean;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ram_external : boolean;
		ext_base_kib : natural
	) return boolean is
	begin
		if addr >= kib_to_addr(ext_base_kib) then
			return true;
		end if;
		if rom_external and addr < kib_to_addr(rom_end_kib) then
			return true;
		end if;
		return ram_external and addr >= kib_to_addr(ram_base_kib) and addr < kib_to_addr(ram_end_kib);
	end function is_external_addr;

	function is_last_word(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural
	) return boolean is
		-- O índice da palavra, sem os dois bits de byte.
		constant WORD : unsigned(29 downto 0) := addr(31 downto 2);

		-- A palavra de índice anterior ao da fronteira dada em KiB, ou todos em 1 quando a fronteira é zero.
		function before(kib : natural) return unsigned is
		begin
			return kib_to_addr(kib)(31 downto 2) - 1;
		end function before;
	begin
		return (rom_end_kib > 0 and WORD = before(rom_end_kib)) or
		       (ram_base_kib > 0 and WORD = before(ram_base_kib)) or
		       (ram_end_kib > 0 and WORD = before(ram_end_kib)) or
		       (ext_base_kib > 0 and WORD = before(ext_base_kib)) or
		       (periph_kib > 0 and WORD = before(periph_kib));
	end function is_last_word;

	function addr_executable(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural
	) return boolean is
	begin
		return addr < kib_to_addr(rom_end_kib) or
		       (addr >= kib_to_addr(ram_base_kib) and addr < kib_to_addr(ram_end_kib)) or
		       (addr >= kib_to_addr(ext_base_kib) and addr < kib_to_addr(periph_kib));
	end function addr_executable;

	function addr_writable(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural;
		periph_slots : std_logic_vector(7 downto 0)
	) return boolean is
	begin
		return (addr >= kib_to_addr(ram_base_kib) and addr < kib_to_addr(ram_end_kib)) or
		       (addr >= kib_to_addr(ext_base_kib) and addr < kib_to_addr(periph_kib)) or
		       (addr >= kib_to_addr(periph_kib) and periph_slots(to_integer(addr(30 downto 28))) = '1');
	end function addr_writable;

	function addr_readable(
		addr         : unsigned;
		rom_end_kib  : natural;
		ram_base_kib : natural;
		ram_end_kib  : natural;
		ext_base_kib : natural;
		periph_kib   : natural;
		periph_slots : std_logic_vector(7 downto 0)
	) return boolean is
	begin
		return addr < kib_to_addr(rom_end_kib) or
		       addr_writable(addr, rom_end_kib, ram_base_kib, ram_end_kib, ext_base_kib, periph_kib, periph_slots);
	end function addr_readable;

end package body mem_map_consts;
