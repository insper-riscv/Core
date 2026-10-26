-- =============================================================================
-- Unidade de sincronização do fluxo de instruções (Extensão Zifencei)
--
-- Executa a instrução FENCE.I (opcode OPCODE_MISC_MEM, funct3 FUNCT3_FENCE_I)
-- no estágio EX do pipeline:
--   1. Com cache de dados (has_dcache = true): solicita o flush da cache de
--      dados (o_flush_req = '1' por um ciclo) e mantém a instrução retida em EX
--      (o_busy = '1') até receber a confirmação de conclusão (i_dc_done = '1'),
--      garantindo que stores anteriores de código já estejam gravados.
--   2. Ao concluir (ou imediatamente quando has_dcache = false), asserta
--      o_take = '1' por um ciclo para que o core invalide a cache de instruções,
--      esvazie os estágios IF/ID e ID/EX e redirecione o PC para PC + 4.
--
-- O sinal i_run indica que o pipeline está avançando sem considerar o próprio
-- o_busy desta unidade. A instrução FENCE comum (funct3 = FUNCT3_FENCE) atua
-- como NOP nesta unidade.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;

entity fencei_unit is
	generic (
		-- Indica a presença de cache de dados write-back que exige flush antes de invalidar I-cache.
		has_dcache : boolean := false
	);
	port (
		-- Sinal de clock do sistema.
		i_clk       : in  std_logic;
		-- Sinal de reset síncrono/assíncrono ativo em '1'.
		i_rst       : in  std_logic;
		-- Indica que há uma instrução válida no estágio EX (não é bolha).
		i_ex_valid  : in  std_logic;
		-- Indica que o pipeline está apto a avançar neste ciclo.
		i_run       : in  std_logic;
		-- Campo opcode (bits [6:0]) da instrução no estágio EX.
		i_opcode    : in  opcode_t;
		-- Campo funct3 (bits [14:12]) da instrução no estágio EX.
		i_funct3    : in  funct3_t;
		-- Pulso de confirmação de término do flush da cache de dados.
		i_dc_done   : in  std_logic := '0';
		-- Pulso de requisição de flush para a cache de dados.
		o_flush_req : out std_logic;
		-- Mantém o estágio EX em stall enquanto aguarda o flush da cache de dados.
		o_busy      : out std_logic;
		-- Pulso que comanda a invalidação da I-cache, flush de IF/ID e ID/EX e salto para PC + 4.
		o_take      : out std_logic
	);
end entity fencei_unit;

architecture rtl of fencei_unit is
	-- Indica que a instrução válida no estágio EX é um FENCE.I.
	signal is_fencei   : std_logic;
	-- Estado registrado que indica espera pelo término do flush da cache de dados.
	signal waiting     : std_logic := '0';
	-- Próximo estado do flip-flop de espera do flush da cache de dados.
	signal waiting_nxt : std_logic;
begin

	is_fencei <= '1' when (i_ex_valid = '1' and i_opcode = OPCODE_MISC_MEM and i_funct3 = FUNCT3_FENCE_I) else '0';

	gen_dc : if has_dcache generate

		o_flush_req <= '1' when (is_fencei = '1' and i_run = '1' and waiting = '0') else '0';

		o_busy      <= '1' when ((is_fencei = '1' and i_run = '1' and waiting = '0') or 
								(waiting = '1' and i_dc_done = '0')) 
							else '0';

		o_take      <= '1' when (waiting = '1' and i_dc_done = '1' and is_fencei = '1') else '0';

		waiting_nxt <= '1' when (is_fencei = '1' and i_run = '1' and waiting = '0') else
		               '0' when (waiting = '1' and i_dc_done = '1') else
		               waiting;

		u_waiting_ff : entity work.flip_flop
			port map (
				i_d      => waiting_nxt,
				o_d      => waiting,
				i_enable => '1',
				i_clk    => i_clk,
				i_rst    => i_rst
			);

	else generate
		o_flush_req <= '0';
		o_busy      <= '0';
		o_take      <= '1' when (is_fencei = '1' and i_run = '1') else '0';
	end generate gen_dc;

end architecture rtl;
