-- =============================================================================
-- Decodificador da dica pause da extensão Zihintpause
--
-- Identifica no estágio ID a palavra de pause (FENCE com pred = W, succ = 0,
-- rs1 = rd = x0). A dica é um HINT: executa como nop, nunca gera exceção de
-- instrução ilegal e não escreve registrador. O pipeline em ordem não tem
-- fio de execução vizinho a ceder, então pause não adiciona espera.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.config_pkg.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;
use work.zihintpause_consts.all;

entity zihintpause_decode is
	port (
		-- Instrução de 32 bits presente no estágio ID.
		i_instr   : in  word_t;
		-- Indica que a instrução é pause.
		o_is_hint : out std_logic
	);
end entity zihintpause_decode;

architecture rtl of zihintpause_decode is
	-- Alias para o campo opcode (bits [6:0]) da instrução.
	alias opcode : opcode_t is i_instr(6 downto 0);
	-- Alias para o campo rd (bits [11:7]) da instrução.
	alias rd     : std_logic_vector(4 downto 0) is i_instr(11 downto 7);
	-- Alias para o campo funct3 (bits [14:12]) da instrução.
	alias funct3 : funct3_t is i_instr(14 downto 12);
	-- Alias para o campo rs1 (bits [19:15]) da instrução.
	alias rs1    : std_logic_vector(4 downto 0) is i_instr(19 downto 15);
begin

	o_is_hint <= '1' when (opcode = OPCODE_MISC_MEM and funct3 = FUNCT3_FENCE and
	                       rd = ZIHINTPAUSE_REG_ZERO and rs1 = ZIHINTPAUSE_REG_ZERO and
	                       i_instr(31 downto 20) = ZIHINTPAUSE_FM_PRED_SUCC)
	             else '0';

end architecture rtl;
