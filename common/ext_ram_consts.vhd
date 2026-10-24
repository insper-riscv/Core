-- =============================================================================
-- Constantes de modo do extensor da memória de dados (ext_ram_op_t)
--
-- Define os códigos de 3 bits (EXT_RAM_*) que selecionam a largura (palavra,
-- meia-palavra ou byte) e o tipo de extensão (sinal ou zero) nos loads.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

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

end package ext_ram_consts;
