-- =============================================================================
-- Unidade de execução da extensão Zicond (condicionais zero)
--
-- Calcula combinacionalmente o resultado de czero.eqz e czero.nez no estágio
-- EX a partir dos operandos já adiantados:
--
--   czero.eqz: rd = 0 se rs2 = 0, senão rs1
--   czero.nez: rd = 0 se rs2 /= 0, senão rs1
--
-- O código de operação (alu_op_t) vindo do estágio ID diz qual das duas
-- instruções está em EX; o_active vale '1' só para elas, e o estágio EX usa
-- esse sinal para escolher o resultado desta unidade no lugar do da ULA.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.zicond_consts.all;

entity zicond_unit is
	port (
		-- Código de operação da instrução em EX (alu_op_t).
		i_op     : in  alu_op_t;
		-- Valor de rs1, com o adiantamento já aplicado.
		i_rs1    : in  word_t;
		-- Valor de rs2, com o adiantamento já aplicado.
		i_rs2    : in  word_t;
		-- Indica que a instrução em EX é czero.eqz ou czero.nez.
		o_active : out std_logic;
		-- Resultado da instrução: zero ou o valor de rs1.
		o_result : out word_t
	);
end entity zicond_unit;

architecture rtl of zicond_unit is
	-- A instrução em EX é czero.eqz.
	signal is_eqz   : std_logic;
	-- A instrução em EX é czero.nez.
	signal is_nez   : std_logic;
	-- O valor de rs2 é zero.
	signal rs2_zero : std_logic;
	-- O resultado é zero em vez de rs1.
	signal zeroed   : std_logic;
begin

	is_eqz   <= '1' when i_op = ALU_CZERO_EQZ else '0';
	is_nez   <= '1' when i_op = ALU_CZERO_NEZ else '0';
	rs2_zero <= '1' when i_rs2 = (i_rs2'range => '0') else '0';
	zeroed   <= (is_eqz and rs2_zero) or (is_nez and not rs2_zero);

	o_active <= is_eqz or is_nez;
	o_result <= (others => '0') when zeroed = '1' else i_rs1;

end architecture rtl;
