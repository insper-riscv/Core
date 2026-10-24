-- =============================================================================
-- Unidade de Detecção de Hazards (Hazard Detection Unit) do pipeline RV32IM
--
-- Detecta dependências de dados do tipo load-use entre os estágios ID e EX e
-- condições de espera (stall) vindas da unidade MulDiv/memória, gerando os
-- sinais de congelamento do PC e do registrador IF/ID e de injeção de bolha
-- (NOP) no registrador ID/EX.
--
-- 1. Load-Use Hazard (Patterson & Hennessy, Seção 4.8):
--    Ocorre quando a instrução no estágio EX é uma leitura de memória
--    (i_idex_re_ram = '1') com registrador destino válido (i_idex_rd /= x0) e
--    a instrução válida em decodificação no estágio ID lê efetivamente rs1 ou
--    rs2 coincidindo com i_idex_rd.
--
-- 2. Stall externo (i_muldiv_busy = '1'):
--    Congela os estágios anteriores quando o estágio EX/MEM aguarda conclusão
--    de operação multiciclo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;

entity hazard_detection_unit is

	port (
		-- Indica que a instrução presente no registrador IF/ID é válida.
		i_ifid_valid  : in  std_logic;
		-- Endereço do registrador fonte rs1 da instrução no estágio ID.
		i_ifid_rs1    : in  reg_t;
		-- Endereço do registrador fonte rs2 da instrução no estágio ID.
		i_ifid_rs2    : in  reg_t;
		-- Campo opcode da instrução no estágio ID (usado para identificar se lê rs1/rs2).
		i_ifid_opcode : in  opcode_t;
		-- Endereço do registrador destino rd da instrução no estágio EX.
		i_idex_rd     : in  reg_t;
		-- Indica que a instrução no estágio EX é uma leitura de memória (load).
		i_idex_re_ram : in  std_logic;
		-- Sinal de ocupação/espera vindo do estágio EX/MEM (MulDiv ou memória).
		i_muldiv_busy : in  std_logic;
		-- Habilita a escrita no registrador PC ('1' = avança, '0' = congela).
		o_pc_we       : out std_logic;
		-- Habilita a escrita no registrador IF/ID ('1' = avança, '0' = congela).
		o_ifid_we     : out std_logic;
		-- Comanda o bubble_mux para injetar NOP no registrador ID/EX ('1' = bolha).
		o_bubble_sel  : out std_logic
	);

end entity hazard_detection_unit;

architecture rtl of hazard_detection_unit is

	-- Indica se a instrução válida no estágio ID utiliza efetivamente o operando rs1.
	signal ifid_uses_rs1   : std_logic;
	-- Indica se a instrução válida no estágio ID utiliza efetivamente o operando rs2.
	signal ifid_uses_rs2   : std_logic;
	-- Indica detecção de conflito de dados load-use entre as instruções em ID e EX.
	signal load_use_hazard : std_logic;
	-- Sinal interno combinado de congelamento do pipeline.
	signal stall           : std_logic;

begin

	-- Identifica se o formato da instrução em ID lê o registrador rs1.
	ifid_uses_rs1 <=
		'1' when (i_ifid_valid = '1' and
		          (i_ifid_opcode = OPCODE_OP     or
		           i_ifid_opcode = OPCODE_OP_IMM or
		           i_ifid_opcode = OPCODE_LOAD   or
		           i_ifid_opcode = OPCODE_STORE  or
		           i_ifid_opcode = OPCODE_BRANCH or
		           i_ifid_opcode = OPCODE_JALR   or
		           i_ifid_opcode = OPCODE_SYSTEM))
		else '0';

	-- Identifica se o formato da instrução em ID lê o registrador rs2 (evita falsos positivos com imediato).
	ifid_uses_rs2 <=
		'1' when (i_ifid_valid = '1' and
		          (i_ifid_opcode = OPCODE_OP    or
		           i_ifid_opcode = OPCODE_STORE or
		           i_ifid_opcode = OPCODE_BRANCH))
		else '0';

	-- Detecta conflito load-use quando a instrução em EX é um load para rd /= x0 usado em ID.
	load_use_hazard <=
		'1' when (i_idex_re_ram = '1' and
		          i_idex_rd /= REG_ZERO and
		          ((ifid_uses_rs1 = '1' and i_idex_rd = i_ifid_rs1) or
		           (ifid_uses_rs2 = '1' and i_idex_rd = i_ifid_rs2)))
		else '0';

	stall <= load_use_hazard or i_muldiv_busy;

	o_pc_we      <= not stall;
	o_ifid_we    <= not stall;
	o_bubble_sel <= stall;

end architecture rtl;
