-- =============================================================================
-- Funções do mapa de memória do processador
--
-- O núcleo conhece só três regiões do config_pkg, a BOOT_MEMORY, a FLASH e a RAM
-- (BOOT_MEMORY_END, FLASH_BASE, FLASH_END, RAM_BASE e RAM_END), e este pacote
-- reúne as decisões de que os pontos de decodificação precisam. A BOOT_MEMORY é
-- sempre alcançada pela porta direta; a FLASH e a RAM, pela porta direta ou pelo
-- barramento, conforme FLASH_ON_BUS e RAM_ON_BUS; todo endereço fora das três
-- regiões sai pela porta externa, que responde com erro quando nada o atende.
-- A busca de instrução, o load e o store seguem a mesma regra de região.
-- Cada projeto fixa os limites no `platform.yaml` da sua plataforma, de onde sai
-- o config_pkg.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;

package mem_map_consts is

    -- O endereço pertence à BOOT_MEMORY, que ocupa [0, BOOT_MEMORY_END).

    function is_boot_addr (addr : unsigned) return boolean;

    -- O endereço pertence à janela da FLASH, [FLASH_BASE, FLASH_END), qualquer que seja o caminho dela.

    function is_flash_addr (addr : unsigned) return boolean;

    -- O endereço pertence à janela da RAM, [RAM_BASE, RAM_END), qualquer que seja o caminho dela.

    function is_ram_addr (addr : unsigned) return boolean;

    -- O endereço é atendido pela porta direta de leitura de dados e de instruções: a BOOT_MEMORY, ou a FLASH quando
    -- ela não está no barramento.

    function is_direct_rom_addr (addr : unsigned) return boolean;

    -- O endereço é atendido pela porta direta da RAM: a janela da RAM quando ela não está no barramento.

    function is_direct_ram_addr (addr : unsigned) return boolean;

    -- O endereço sai pela porta externa: tudo o que as portas diretas não atendem, isto é, a FLASH e a RAM no
    -- barramento e todo endereço fora das três regiões.

    function is_external_addr (addr : unsigned) return boolean;

    -- O endereço está na memória principal, a única em que o acesso desalinhado é executado em hardware (Zicclsm): tudo
    -- o que não é a BOOT_MEMORY nem a FLASH direta, que não repartem um acesso em duas leituras.

    function is_main_addr (addr : unsigned) return boolean;

    -- A palavra do endereço é a última de uma região de caminho próprio: a seguinte pertenceria à região vizinha, que
    -- o acesso desalinhado não alcança com a classificação do primeiro endereço.

    function is_last_word (addr : unsigned) return boolean;

    -- O endereço aceita escrita no mapa do núcleo: tudo menos a BOOT_MEMORY e a FLASH, que são só de leitura. Um
    -- endereço fora das três regiões aceita escrita aqui, e a porta externa responde erro se nada o atende.

    function addr_writable (addr : unsigned) return boolean;

    -- O endereço aceita busca de instrução: a BOOT_MEMORY, a FLASH e a RAM no barramento (pela cache de instruções).

    function addr_executable (addr : unsigned) return boolean;

end package mem_map_consts;

package body mem_map_consts is

    function is_boot_addr (addr : unsigned) return boolean is
    begin

        return addr < BOOT_MEMORY_END;

    end function is_boot_addr;

    function is_flash_addr (addr : unsigned) return boolean is
    begin

        return addr >= FLASH_BASE and addr < FLASH_END;

    end function is_flash_addr;

    function is_ram_addr (addr : unsigned) return boolean is
    begin

        return addr >= RAM_BASE and addr < RAM_END;

    end function is_ram_addr;

    function is_direct_rom_addr (addr : unsigned) return boolean is
    begin

        return is_boot_addr(addr) or ((not FLASH_ON_BUS) and is_flash_addr(addr));

    end function is_direct_rom_addr;

    function is_direct_ram_addr (addr : unsigned) return boolean is
    begin

        return (not RAM_ON_BUS) and is_ram_addr(addr);

    end function is_direct_ram_addr;

    function is_external_addr (addr : unsigned) return boolean is
    begin

        return not (is_direct_rom_addr(addr) or is_direct_ram_addr(addr));

    end function is_external_addr;

    function is_main_addr (addr : unsigned) return boolean is
    begin

        return not is_direct_rom_addr(addr);

    end function is_main_addr;

    function is_last_word (addr : unsigned) return boolean is

        -- O índice da palavra, sem os dois bits de byte.
        constant WORD : unsigned((ADDR_BITS - 3) downto 0) := addr((ADDR_BITS - 1) downto 2);

        -- A palavra de índice anterior ao da fronteira dada, ou todos em 1 quando a fronteira é 2**ADDR_BITS.

        function before (bound : map_addr_t) return unsigned is
        begin

            return bound((ADDR_BITS - 1) downto 2) - 1;

        end function before;

    begin

        return WORD = before(FLASH_BASE) or WORD = before(FLASH_END) or WORD = before(RAM_BASE) or
               WORD = before(RAM_END) or WORD = (WORD'range => '1');

    end function is_last_word;

    function addr_executable (addr : unsigned) return boolean is
    begin

        return is_boot_addr(addr) or is_flash_addr(addr) or (RAM_ON_BUS and is_ram_addr(addr));

    end function addr_executable;

    function addr_writable (addr : unsigned) return boolean is
    begin

        return not (is_boot_addr(addr) or is_flash_addr(addr));

    end function addr_writable;

end package body mem_map_consts;
