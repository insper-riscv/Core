-- =============================================================================
-- Constantes de seleção de fonte do estágio Write-Back (wb_sel_t)
--
-- Define os códigos de 1 bit (WB_SEL_*) que selecionam qual resultado será
-- gravado no banco de registradores ao final do pipeline.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package wb_sel_consts is

	-- Seleciona o resultado do estágio EX (ULA, MulDiv, CSR e PC + 4 de JAL e JALR).
	constant WB_SEL_ALU : wb_sel_t := "0";
	-- Seleciona o dado lido e estendido da memória de dados (instruções de load).
	constant WB_SEL_RAM : wb_sel_t := "1";

end package wb_sel_consts;
