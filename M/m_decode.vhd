-- =============================================================================
-- Decodificador de instruções da extensão M (Multiplicação e Divisão Inteira)
--
-- Identifica no estágio ID as instruções R-type pertencentes à extensão M
-- (opcode = OPCODE_OP e funct7 = FUNCT7_MULDIV: MUL, MULH, MULHSU, MULHU,
-- DIV, DIVU, REM, REMU) e ativa os sinais de controle necessários:
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

	-- Sinal interno que indica reivindicação da instrução pela extensão M.
	signal is_m_instr : std_logic;
begin

	is_m_instr <= '1' when (opcode = OPCODE_OP and funct7 = FUNCT7_MULDIV) else '0';

	o_is_muldiv  <= is_m_instr;
	o_we_reg     <= is_m_instr;
	o_sel_pc_rs1 <= is_m_instr;

end architecture rtl;
