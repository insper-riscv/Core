-- =============================================================================
-- Decodificador das dicas da extensão Zihintntl (ntl.p1, ntl.pall, ntl.s1, ntl.all)
--
-- Identifica no estágio ID as quatro codificações de 32 bits (ADD com rd = x0,
-- rs1 = x0 e rs2 de x2 a x5). Uma dica é um HINT: executa como nop, nunca gera
-- exceção de instrução ilegal e não escreve registrador. O núcleo não tem
-- hierarquia de cache com domínios de localidade, então a dica não muda nada
-- além de ser reconhecida.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;
use work.funct7_consts.all;
use work.zihintntl_consts.all;

entity zihintntl_decode is
	port (
		-- Instrução de 32 bits presente no estágio ID.
		i_instr   : in  word_t;
		-- Indica que a instrução é uma das quatro dicas ntl.*.
		o_is_hint : out std_logic
	);
end entity zihintntl_decode;

architecture rtl of zihintntl_decode is
	-- Alias para o campo opcode (bits [6:0]) da instrução.
	alias opcode : opcode_t is i_instr(6 downto 0);
	-- Alias para o campo rd (bits [11:7]) da instrução.
	alias rd     : std_logic_vector(4 downto 0) is i_instr(11 downto 7);
	-- Alias para o campo funct3 (bits [14:12]) da instrução.
	alias funct3 : funct3_t is i_instr(14 downto 12);
	-- Alias para o campo rs1 (bits [19:15]) da instrução.
	alias rs1    : std_logic_vector(4 downto 0) is i_instr(19 downto 15);
	-- Alias para o campo rs2 (bits [24:20]) da instrução.
	alias rs2    : std_logic_vector(4 downto 0) is i_instr(24 downto 20);
	-- Alias para o campo funct7 (bits [31:25]) da instrução.
	alias funct7 : funct7_t is i_instr(31 downto 25);
begin

	o_is_hint <= '1' when (opcode = OPCODE_OP and funct3 = FUNCT3_ADD_SUB and funct7 = FUNCT7_DEFAULT and
	                       rd = ZIHINTNTL_REG_ZERO and rs1 = ZIHINTNTL_REG_ZERO and
	                       unsigned(rs2) >= unsigned(ZIHINTNTL_RS2_FIRST) and
	                       unsigned(rs2) <= unsigned(ZIHINTNTL_RS2_LAST))
	             else '0';

end architecture rtl;
