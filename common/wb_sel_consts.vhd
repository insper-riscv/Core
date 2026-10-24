-- =============================================================================
-- Constantes de seleção de fonte do estágio Write-Back (wb_sel_t)
--
-- Define os códigos de 2 bits (WB_SEL_*) que selecionam qual resultado será
-- gravado no banco de registradores ao final do pipeline.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package wb_sel_consts is

	-- Seleciona o resultado da ULA (ou da unidade MulDiv).
	constant WB_SEL_ALU : wb_sel_t := "00";
	-- Seleciona PC + 4 (instruções de salto JAL e JALR).
	constant WB_SEL_PC4 : wb_sel_t := "01";
	-- Seleciona o dado lido e estendido da memória de dados (instruções de load).
	constant WB_SEL_RAM : wb_sel_t := "10";

end package wb_sel_consts;
