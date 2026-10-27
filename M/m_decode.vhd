-- =============================================================================
-- Decodificador de instruções da extensão M (Multiplicação e Divisão Inteira)
--
-- Identifica no estágio ID as instruções R-type pertencentes à extensão M
-- (opcode = OPCODE_OP e funct7 = FUNCT7_MULDIV: MUL, MULH, MULHSU, MULHU,
-- DIV, DIVU, REM, REMU). Com has_div = false (extensão Zmmul) só as quatro
-- multiplicações (funct3(2) = '0') são reivindicadas; DIV, DIVU, REM e REMU
-- ficam sem dono e a unidade de controle as trata como ilegais. Ativa os sinais de controle necessários:
--   - o_is_muldiv  = '1' (seleciona o resultado da unidade multdiv no estágio EX)
--   - o_we_reg     = '1' (habilita escrita no registrador de destino rd no WB)
--   - o_sel_pc_rs1 = '1' (seleciona rs1 como operando A no estágio EX)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct7_consts.all;

entity m_decode is
	generic (
		-- Reivindica também as divisões e restos (extensão M completa); '0' deixa só a Zmmul.
		has_div : boolean := true
	);
	port (
		-- Instrução de 32 bits presente no estágio ID.
		i_instr      : in  word_t;
		-- Indica que a instrução pertence à extensão M (multiplicação ou divisão).
		o_is_muldiv  : out std_logic;
		-- Habilita a escrita no banco de registradores para a instrução M.
		o_we_reg     : out std_logic;
		-- Seleciona o registrador rs1 como primeiro operando no estágio EX.
		o_sel_pc_rs1 : out std_logic
	);
end entity m_decode;

architecture rtl of m_decode is
	-- Alias para o campo opcode (bits [6:0]) da instrução.
	alias opcode : opcode_t is i_instr(6 downto 0);
	-- Alias para o campo funct7 (bits [31:25]) da instrução.
	alias funct7 : funct7_t is i_instr(31 downto 25);
	-- Alias para o campo funct3 (bits [14:12]) da instrução.
	alias funct3 : funct3_t is i_instr(14 downto 12);

	-- Sinal interno que indica reivindicação da instrução pela extensão M.
	signal is_m_instr : std_logic;
	-- Indica que o funct3 está entre os que esta configuração implementa (multiplicações sempre; divisões só com has_div).
	signal is_claimed_funct3 : std_logic;
begin

	is_claimed_funct3 <= '1' when (has_div or funct3(2) = '0') else '0';

	is_m_instr <= '1' when (opcode = OPCODE_OP and funct7 = FUNCT7_MULDIV and is_claimed_funct3 = '1') else '0';

	o_is_muldiv  <= is_m_instr;
	o_we_reg     <= is_m_instr;
	o_sel_pc_rs1 <= is_m_instr;

end architecture rtl;
