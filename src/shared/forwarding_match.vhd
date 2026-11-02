-- =============================================================================
-- Comparação do adiantamento no estágio ID (forwarding_match)
--
-- Compara os registradores fonte da instrução em ID com os destinos das três
-- instruções à frente dela e devolve, por operando, quais delas escrevem o
-- registrador. A instrução em ID será a de EX no ciclo seguinte, e as três de
-- hoje (ID/EX, EX/MEM e MEM/WB) serão então as de EX/MEM, MEM/WB e WB2. O
-- resultado é registrado em ID/EX, de modo que o EX escolhe a fonte só com
-- elementos já registrados, sem comparar índices de registrador.
--
-- Os bits de cada casamento seguem as posições de fwd_match_t (fwd_consts):
-- FWD_MATCH_EXMEM para a instrução hoje em ID/EX, FWD_MATCH_MEMWB para a de
-- hoje em EX/MEM e FWD_MATCH_WB2 para a de hoje em MEM/WB.
--
-- Um destino x0 nunca casa. A validade das três instruções é conferida no EX,
-- porque uma delas pode ser descartada entre os dois ciclos.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.fwd_consts.all;

entity forwarding_match is

	port (
		-- Registrador fonte rs1 da instrução em ID.
		i_rs1       : in  reg_t;
		-- Registrador fonte rs2 da instrução em ID.
		i_rs2       : in  reg_t;
		-- Registrador destino rd da instrução em ID/EX.
		i_ex_rd     : in  reg_t;
		-- Habilitação de escrita em registrador da instrução em ID/EX.
		i_ex_we     : in  std_logic;
		-- Registrador destino rd da instrução em EX/MEM.
		i_mem_rd    : in  reg_t;
		-- Habilitação de escrita em registrador da instrução em EX/MEM.
		i_mem_we    : in  std_logic;
		-- Registrador destino rd da instrução em MEM/WB.
		i_wb_rd     : in  reg_t;
		-- Habilitação de escrita em registrador da instrução em MEM/WB.
		i_wb_we     : in  std_logic;
		-- Casamentos de rs1 com as três instruções à frente, nas posições de fwd_match_t.
		o_match_rs1 : out fwd_match_t;
		-- Casamentos de rs2 com as três instruções à frente, nas posições de fwd_match_t.
		o_match_rs2 : out fwd_match_t
	);

end entity forwarding_match;

architecture rtl of forwarding_match is

	-- Indica que a instrução escreve em um registrador que não é x0 e que ele é o operando pedido.
	function writes_operand(we : std_logic; rd : reg_t; rs : reg_t) return std_logic is
	begin
		if we = '1' and rd /= REG_ZERO and rd = rs then
			return '1';
		end if;
		return '0';
	end function;

begin

	o_match_rs1(FWD_MATCH_EXMEM) <= writes_operand(i_ex_we,  i_ex_rd,  i_rs1);
	o_match_rs1(FWD_MATCH_MEMWB) <= writes_operand(i_mem_we, i_mem_rd, i_rs1);
	o_match_rs1(FWD_MATCH_WB2)   <= writes_operand(i_wb_we,  i_wb_rd,  i_rs1);

	o_match_rs2(FWD_MATCH_EXMEM) <= writes_operand(i_ex_we,  i_ex_rd,  i_rs2);
	o_match_rs2(FWD_MATCH_MEMWB) <= writes_operand(i_mem_we, i_mem_rd, i_rs2);
	o_match_rs2(FWD_MATCH_WB2)   <= writes_operand(i_wb_we,  i_wb_rd,  i_rs2);

end architecture rtl;
