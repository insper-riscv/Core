-- =============================================================================
-- Constantes da extensão Zicond (condicionais zero)
--
-- Define a codificação das duas instruções da extensão (czero.eqz e czero.nez,
-- capítulo 10 do manual não privilegiado) e os códigos de operação que o
-- estágio ID entrega ao estágio EX no campo alu_op_t. Os dois códigos não
-- coincidem com nenhuma operação da ULA (ver alu_consts), de modo que o EX
-- reconhece a instrução da extensão sem um sinal novo no registrador ID/EX.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package zicond_consts is

	-- Valor de funct7 (bits [31:25]) das duas instruções da extensão.
	constant FUNCT7_ZICOND         : funct7_t := "0000111";
	-- Valor de funct3 (bits [14:12]) de czero.eqz.
	constant FUNCT3_CZERO_EQZ      : funct3_t := "101";
	-- Valor de funct3 (bits [14:12]) de czero.nez.
	constant FUNCT3_CZERO_NEZ      : funct3_t := "111";

	-- Código de operação de czero.eqz: rd recebe zero quando rs2 vale zero e rs1 nos demais casos.
	constant ALU_CZERO_EQZ         : alu_op_t := "01100";
	-- Código de operação de czero.nez: rd recebe zero quando rs2 não vale zero e rs1 nos demais casos.
	constant ALU_CZERO_NEZ         : alu_op_t := "01110";

end package zicond_consts;
