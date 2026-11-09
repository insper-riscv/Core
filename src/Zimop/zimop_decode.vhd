-- =============================================================================
-- Decodificador de instruções da extensão Zimop (May-Be-Operations)
--
-- Identifica no estágio ID as 32 codificações de mop.r.n e as 8 de mop.rr.n
-- (classe SYSTEM, funct3 = FUNCT3_SYSTEM_RESERVED, campos fixos em
-- zimop_consts). A instrução escreve zero em rd e nunca gera exceção de
-- instrução ilegal. Para isso o decodificador:
--   - habilita a escrita em rd (o_we_reg = '1');
--   - escolhe uma operação da ULA sem resultado de dados (ALU_BGEU), cujo
--     resultado é zero, já que a ULA só seleciona resultado de dados nas
--     demais operações;
--   - apresenta aos estágios seguintes o opcode de uma instrução aritmética
--     comum (OPCODE_OP_IMM), para que a unidade de exceções não trate a
--     codificação como SYSTEM não suportada.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.config_pkg.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;
use work.alu_consts.all;
use work.zimop_consts.all;

entity zimop_decode is
	port (
		-- Instrução de 32 bits presente no estágio ID.
		i_instr      : in  word_t;
		-- Indica que a instrução é um mop.r.n ou um mop.rr.n.
		o_is_zimop   : out std_logic;
		-- Habilita a escrita de zero no registrador destino rd.
		o_we_reg     : out std_logic;
		-- Operação da ULA sem resultado de dados, que faz o resultado valer zero.
		o_alu_op     : out alu_op_t;
		-- Opcode apresentado ao estágio EX no lugar de SYSTEM.
		o_opcode     : out opcode_t
	);
end entity zimop_decode;

architecture rtl of zimop_decode is
	-- Alias para o campo opcode (bits [6:0]) da instrução.
	alias opcode : opcode_t is i_instr(6 downto 0);
	-- Alias para o campo funct3 (bits [14:12]) da instrução.
	alias funct3 : funct3_t is i_instr(14 downto 12);

	-- Campos fixos comuns a mop.r.n e mop.rr.n estão no bit 31 e nos bits [29:28].
	signal is_common : std_logic;
	-- Indica uma codificação de mop.r.n.
	signal is_mop_r  : std_logic;
	-- Indica uma codificação de mop.rr.n.
	signal is_mop_rr : std_logic;
	-- Indica uma das 40 codificações.
	signal is_mop    : std_logic;
begin

	is_common <= '1' when (opcode = OPCODE_SYSTEM and funct3 = FUNCT3_SYSTEM_RESERVED and
	                       i_instr(31) = ZIMOP_BIT31 and i_instr(29 downto 28) = ZIMOP_BITS_29_28)
	             else '0';

	is_mop_r  <= '1' when (is_common = '1' and i_instr(25) = ZIMOP_BIT25_R and
	                       i_instr(24 downto 22) = ZIMOP_BITS_24_22)
	             else '0';

	is_mop_rr <= '1' when (is_common = '1' and i_instr(25) = ZIMOP_BIT25_RR) else '0';

	is_mop <= is_mop_r or is_mop_rr;

	o_is_zimop <= is_mop;
	o_we_reg   <= is_mop;
	o_alu_op   <= ALU_BGEU;
	o_opcode   <= OPCODE_OP_IMM;

end architecture rtl;
