-- =============================================================================
-- Funções do mapa de memória do processador
--
-- O mapa vem em bytes do config_pkg (BOOT_MEMORY_BITS, ROM_END, RAM_BASE,
-- RAM_END, EXT_BASE, PERIPH_BASE, ROM_EXTERNAL e RAM_EXTERNAL), e este pacote
-- reúne as decisões de que os pontos de decodificação precisam (BOOT_MEMORY,
-- ROM interna, janela externa e janela de periféricos). Cada projeto fixa os
-- limites no `platform.yaml` da sua plataforma, de onde sai o config_pkg.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;

package mem_map_consts is

	-- Endereço exclusivo do fim da BOOT_MEMORY, que ocupa [0, 2**BOOT_MEMORY_BITS).
	function boot_memory_end return map_addr_t;

	-- Endereço exclusivo do fim da ROM interna, ou zero quando a ROM é externa.
	function internal_rom_end return map_addr_t;

	-- Início da memória principal: logo depois da ROM interna; com a ROM externa, a base externa quando a ROM é vazia
	-- ou o fim da BOOT_MEMORY, pois a ROM externa, que começa ali, é lida e escrita pela porta externa como a RAM.
	function main_mem_base return map_addr_t;

	-- O endereço sai pela porta externa: a janela externa, a ROM quando é externa ou a RAM quando é externa.
	function is_external_addr(addr : unsigned) return boolean;

	-- A palavra do endereço é a última de uma região: a seguinte pertenceria à região vizinha.
	function is_last_word(addr : unsigned) return boolean;

	-- O endereço está no intervalo de leitura válido do mapa: ROM, RAM, janela externa ou um slot de periférico ocupado.
	function addr_readable(addr : unsigned; periph_slots : std_logic_vector(7 downto 0)) return boolean;

	-- O endereço aceita escrita: o mapa válido sem a ROM (BOOT_MEMORY e FLASH são só de leitura).
	function addr_writable(addr : unsigned; periph_slots : std_logic_vector(7 downto 0)) return boolean;

	-- O endereço aceita busca de instrução: ROM, RAM e janela externa (nunca periférico).
	function addr_executable(addr : unsigned) return boolean;

end package mem_map_consts;

package body mem_map_consts is

	function boot_memory_end return map_addr_t is
	begin
		return shift_left(to_unsigned(1, ADDR_BITS + 1), BOOT_MEMORY_BITS);
	end function boot_memory_end;

	function internal_rom_end return map_addr_t is
	begin
		if ROM_EXTERNAL then
			return to_unsigned(0, ADDR_BITS + 1);
		end if;
		return ROM_END;
	end function internal_rom_end;

	function main_mem_base return map_addr_t is
	begin
		if ROM_EXTERNAL and ROM_END = 0 then
			return EXT_BASE;
		end if;
		if ROM_EXTERNAL then
			return boot_memory_end;
		end if;
		return ROM_END;
	end function main_mem_base;

	function is_external_addr(addr : unsigned) return boolean is
	begin
		if addr >= EXT_BASE then
			return true;
		end if;
		if ROM_EXTERNAL and addr < ROM_END then
			return true;
		end if;
		return RAM_EXTERNAL and addr >= RAM_BASE and addr < RAM_END;
	end function is_external_addr;

	function is_last_word(addr : unsigned) return boolean is
		-- O índice da palavra, sem os dois bits de byte.
		constant WORD : unsigned((ADDR_BITS - 3) downto 0) := addr((ADDR_BITS - 1) downto 2);

		-- A palavra de índice anterior ao da fronteira dada, ou todos em 1 quando a fronteira é zero.
		function before(bound : map_addr_t) return unsigned is
		begin
			return bound((ADDR_BITS - 1) downto 2) - 1;
		end function before;
	begin
		return (ROM_END > 0 and WORD = before(ROM_END)) or
		       (RAM_BASE > 0 and WORD = before(RAM_BASE)) or
		       (RAM_END > 0 and WORD = before(RAM_END)) or
		       (EXT_BASE > 0 and WORD = before(EXT_BASE)) or
		       (PERIPH_BASE > 0 and WORD = before(PERIPH_BASE));
	end function is_last_word;

	function addr_executable(addr : unsigned) return boolean is
	begin
		return addr < ROM_END or
		       (addr >= RAM_BASE and addr < RAM_END) or
		       (addr >= EXT_BASE and addr < PERIPH_BASE);
	end function addr_executable;

	function addr_writable(addr : unsigned; periph_slots : std_logic_vector(7 downto 0)) return boolean is
	begin
		return (addr >= RAM_BASE and addr < RAM_END) or
		       (addr >= EXT_BASE and addr < PERIPH_BASE) or
		       (addr >= PERIPH_BASE and periph_slots(to_integer(addr((ADDR_BITS - 2) downto (ADDR_BITS - 4)))) = '1');
	end function addr_writable;

	function addr_readable(addr : unsigned; periph_slots : std_logic_vector(7 downto 0)) return boolean is
	begin
		return addr < ROM_END or addr_writable(addr, periph_slots);
	end function addr_readable;

end package body mem_map_consts;
