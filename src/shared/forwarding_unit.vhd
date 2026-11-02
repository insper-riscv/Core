-- =============================================================================
-- Seleção do adiantamento no estágio EX (forwarding_unit)
--
-- Escolhe, para cada operando, a fonte do multiplexador de adiantamento a
-- partir dos casamentos que o estágio ID calculou e registrou (forwarding_match)
-- e da validade das instruções à frente, também registrada. Não compara
-- índices de registrador: cada bit de seleção é função de seis sinais de
-- flip-flops.
--
-- Codificação de o_fwd_rs1 / o_fwd_rs2 (constantes de fwd_consts):
--   FWD_EXMEM = resultado de EX registrado em EX/MEM (a mais nova)
--   FWD_MEMWB = resultado de EX registrado em MEM/WB
--   FWD_WB2   = dado final de write-back registrado em WB2 (a mais antiga)
--   FWD_NONE  = valor lido do banco de registradores no estágio ID
--
-- Prioridade: EX/MEM > MEM/WB > WB2. Quando duas instruções escrevem no mesmo
-- registrador, vale a mais nova que ainda é válida; se ela foi descartada
-- depois do ID, a seleção cai para a seguinte.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.fwd_consts.all;

entity forwarding_unit is

	port (
		-- Casamentos de rs1 com EX/MEM, MEM/WB e WB2, calculados no estágio ID, nas posições de fwd_match_t.
		i_match_rs1  : in  fwd_match_t;
		-- Casamentos de rs2 com EX/MEM, MEM/WB e WB2, calculados no estágio ID, nas posições de fwd_match_t.
		i_match_rs2  : in  fwd_match_t;
		-- A instrução em EX/MEM é válida e escreve em registrador.
		i_exmem_ok   : in  std_logic;
		-- A instrução em MEM/WB é válida e escreve em registrador.
		i_memwb_ok   : in  std_logic;
		-- A instrução em WB2 escreve em registrador.
		i_wb2_ok     : in  std_logic;
		-- Seletor do multiplexador de adiantamento para o operando rs1 no estágio EX.
		o_fwd_rs1    : out fwd_sel_t;
		-- Seletor do multiplexador de adiantamento para o operando rs2 no estágio EX.
		o_fwd_rs2    : out fwd_sel_t
	);

end entity forwarding_unit;

architecture rtl of forwarding_unit is

	-- Escolhe a fonte mais nova que casa e ainda é válida.
	function select_source(match : fwd_match_t; exmem_ok, memwb_ok, wb2_ok : std_logic) return fwd_sel_t is
	begin
		if match(FWD_MATCH_EXMEM) = '1' and exmem_ok = '1' then
			return FWD_EXMEM;
		elsif match(FWD_MATCH_MEMWB) = '1' and memwb_ok = '1' then
			return FWD_MEMWB;
		elsif match(FWD_MATCH_WB2) = '1' and wb2_ok = '1' then
			return FWD_WB2;
		end if;
		return FWD_NONE;
	end function;

begin

	o_fwd_rs1 <= select_source(i_match_rs1, i_exmem_ok, i_memwb_ok, i_wb2_ok);
	o_fwd_rs2 <= select_source(i_match_rs2, i_exmem_ok, i_memwb_ok, i_wb2_ok);

end architecture rtl;
