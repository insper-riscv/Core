-- =============================================================================
-- Extensor de imediato da arquitetura RISC-V RV32I
--
-- Extrai os campos de imediato codificados nos bits [31:7] da instrução (ou da
-- instrução completa de 32 bits) e estende com sinal ou zero para 32 bits,
-- conforme o seletor de formato i_op (EXT_IMM_*):
--   - EXT_IMM_U       : instr[31:12] << 12 (LUI, AUIPC)
--   - EXT_IMM_I       : sext(instr[31:20]) (I-type aritmético, loads, JALR, CSR)
--   - EXT_IMM_I_SHAMT : zext(instr[24:20]) (SLLI, SRLI, SRAI)
--   - EXT_IMM_J       : sext(instr[31] & instr[19:12] & instr[20] & instr[30:21] & '0') (JAL)
--   - EXT_IMM_B       : sext(instr[31] & instr[7] & instr[30:25] & instr[11:8] & '0') (BRANCH)
--   - EXT_IMM_S       : sext(instr[31:25] & instr[11:7]) (STORE)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.ext_imm_consts.all;

entity extender_imm is
	port (
		-- Bits [31:7] da instrução RISC-V contendo os campos de imediato.
		i_instr : in  std_logic_vector(31 downto 7);
		-- Seletor de formato de imediato (EXT_IMM_U, EXT_IMM_I, EXT_IMM_I_SHAMT, EXT_IMM_J, EXT_IMM_S, EXT_IMM_B).
		i_op    : in  ext_imm_op_t;
		-- Imediato de 32 bits estendido e alinhado.
		o_imm   : out word_t
	);
end entity extender_imm;

architecture rtl of extender_imm is
begin

	with i_op select
		o_imm <=
			-- Formato U-type: instr[31:12] << 12
			i_instr(31 downto 12) & (11 downto 0 => '0')
				when EXT_IMM_U,
			-- Formato I-type: sext(instr[31:20])
			(31 downto 12 => i_instr(31)) & i_instr(31 downto 20)
				when EXT_IMM_I,
			-- Formato I-type shamt: zext(instr[24:20])
			(31 downto 5 => '0') & i_instr(24 downto 20)
				when EXT_IMM_I_SHAMT,
			-- Formato J-type (JAL): sext(instr[31] & instr[19:12] & instr[20] & instr[30:21] & '0')
			(31 downto 21 => i_instr(31)) & i_instr(31) & i_instr(19 downto 12) & i_instr(20) & i_instr(30 downto 21) & '0'
				when EXT_IMM_J,
			-- Formato B-type (BRANCH): sext(instr[31] & instr[7] & instr[30:25] & instr[11:8] & '0')
			(31 downto 13 => i_instr(31)) & i_instr(31) & i_instr(7) & i_instr(30 downto 25) & i_instr(11 downto 8) & '0'
				when EXT_IMM_B,
			-- Formato S-type (STORE): sext(instr[31:25] & instr[11:7])
			(31 downto 12 => i_instr(31)) & i_instr(31 downto 25) & i_instr(11 downto 7)
				when EXT_IMM_S,
			-- Valor padrão seguro para seletores não utilizados
			(others => '0')
				when others;

end architecture rtl;
