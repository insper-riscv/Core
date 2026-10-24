-- =============================================================================
-- Constantes de formato do extensor de imediato (ext_imm_op_t)
--
-- Define os códigos de 3 bits (EXT_IMM_*) que selecionam como os campos de
-- imediato da instrução RISC-V são extraídos e estendidos para 32 bits.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package ext_imm_consts is

	-- Formato U-type (LUI, AUIPC): instr[31:12] << 12.
	constant EXT_IMM_U       : ext_imm_op_t := "000";
	-- Formato I-type de 12 bits com extensão de sinal (ADDI, LW, JALR, etc.).
	constant EXT_IMM_I       : ext_imm_op_t := "001";
	-- Formato I-type shift amount de 5 bits com extensão por zero (SLLI, SRLI, SRAI).
	constant EXT_IMM_I_SHAMT : ext_imm_op_t := "010";
	-- Formato J-type de 21 bits com extensão de sinal (JAL).
	constant EXT_IMM_J       : ext_imm_op_t := "011";
	-- Formato S-type de 12 bits com extensão de sinal (SB, SH, SW).
	constant EXT_IMM_S       : ext_imm_op_t := "100";
	-- Formato B-type de 13 bits com extensão de sinal (BEQ, BNE, BLT, BGE, BLTU, BGEU).
	constant EXT_IMM_B       : ext_imm_op_t := "101";

end package ext_imm_consts;
