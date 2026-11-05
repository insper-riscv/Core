-- =============================================================================
-- Decodificador de instruções da extensão Zicond (condicionais zero)
--
-- Identifica no estágio ID as duas instruções R-type da extensão
-- (opcode = OPCODE_OP e funct7 = FUNCT7_ZICOND: czero.eqz com
-- funct3 = FUNCT3_CZERO_EQZ e czero.nez com funct3 = FUNCT3_CZERO_NEZ). As
-- demais combinações de funct3 com esse funct7 não são reivindicadas, e a
-- unidade de controle as trata como ilegais. Ativa os sinais necessários:
--   - o_is_zicond  = '1' (a instrução é legal e pertence à extensão)
--   - o_alu_op     = código ALU_CZERO_EQZ ou ALU_CZERO_NEZ, que o estágio EX
--                    reconhece para escolher o resultado da zicond_unit
--   - o_we_reg     = '1' (habilita escrita no registrador de destino rd no WB)
--   - o_sel_pc_rs1 = '1' (seleciona rs1 como operando A no estágio EX)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.zicond_consts.all;

entity zicond_decode is
	port (
		-- Instrução de 32 bits presente no estágio ID.
		i_instr      : in  word_t;
		-- Indica que a instrução é czero.eqz ou czero.nez.
		o_is_zicond  : out std_logic;
		-- Código de operação entregue ao estágio EX; vale zero fora da extensão.
		o_alu_op     : out alu_op_t;
		-- Habilita a escrita no banco de registradores para a instrução da extensão.
		o_we_reg     : out std_logic;
		-- Seleciona o registrador rs1 como primeiro operando no estágio EX.
		o_sel_pc_rs1 : out std_logic
	);
end entity zicond_decode;

architecture rtl of zicond_decode is
	-- Alias para o campo opcode (bits [6:0]) da instrução.
	alias opcode : opcode_t is i_instr(6 downto 0);
	-- Alias para o campo funct7 (bits [31:25]) da instrução.
	alias funct7 : funct7_t is i_instr(31 downto 25);
	-- Alias para o campo funct3 (bits [14:12]) da instrução.
	alias funct3 : funct3_t is i_instr(14 downto 12);

	-- A instrução é czero.eqz.
	signal is_eqz : std_logic;
	-- A instrução é czero.nez.
	signal is_nez : std_logic;
begin

	is_eqz <= '1' when (opcode = OPCODE_OP and funct7 = FUNCT7_ZICOND and funct3 = FUNCT3_CZERO_EQZ) else '0';
	is_nez <= '1' when (opcode = OPCODE_OP and funct7 = FUNCT7_ZICOND and funct3 = FUNCT3_CZERO_NEZ) else '0';

	o_is_zicond  <= is_eqz or is_nez;
	o_we_reg     <= is_eqz or is_nez;
	o_sel_pc_rs1 <= is_eqz or is_nez;
	o_alu_op     <= ALU_CZERO_EQZ when is_eqz = '1' else
	                ALU_CZERO_NEZ when is_nez = '1' else
	                (others => '0');

end architecture rtl;
