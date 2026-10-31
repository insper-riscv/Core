-- =============================================================================
-- Estágio ID (Instruction Decode) do Pipeline RV32
--
-- Encapsula a decodificação de instruções, leitura/escrita no banco de
-- registradores e detecção de hazards no segundo estágio do pipeline:
--   1. Unidade de controle base RV32I (control_unit) e decodificadores opcionais
--      das extensões M (m_decode) e Zicsr (csr_decode).
--   2. Extensor de imediatos de 32 bits (extender_imm).
--   3. Banco de 32 registradores de uso geral (reg_file), recebendo a escrita
--      vinda do estágio WB.
--   4. Unidade de detecção de hazards de load-use e stall de unidades
--      multiciclo (hazard_detection_unit) e mux de inserção de bolha (bubble_mux).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.ext_imm_consts.all;
use work.opcode_consts.all;
use work.funct3_consts.all;
use work.alu_consts.all;

entity stage_id is
	generic (
		-- Habilita o decodificador da extensão M completa (m_decode, multiplicação e divisão).
		has_m     : boolean := false;
		-- Habilita o decodificador só da multiplicação (extensão Zmmul); has_m já a inclui.
		has_zmmul : boolean := false;
		-- Habilita o decodificador da extensão Zicsr (csr_decode).
		has_zicsr : boolean := false;
		-- Declara o FENCE.I legal; sem a extensão Zifencei ele é uma instrução ilegal.
		has_zifencei : boolean := false
	);
	port (
		-- Sinal de clock principal do processador.
		i_clk         : in  std_logic;
		-- Sinal de reset ativo em '1'.
		i_rst         : in  std_logic;
		-- Bit de validade da instrução presente no registrador IF/ID.
		i_ifid_valid  : in  std_logic;
		-- Palavra de instrução de 32 bits presente no registrador IF/ID.
		i_instr       : in  word_t;
		-- Habilitação de escrita no banco de registradores vinda do estágio WB.
		i_wb_we       : in  std_logic;
		-- Endereço do registrador destino rd vindo do estágio WB.
		i_wb_rd       : in  reg_t;
		-- Dado de 32 bits a ser escrito no banco de registradores vindo do estágio WB.
		i_wb_data     : in  word_t;
		-- Endereço do registrador destino rd da instrução no estágio MEM (para detecção load-use).
		i_mem_rd      : in  reg_t;
		-- Indica se a instrução no estágio MEM é uma leitura de memória (load).
		i_mem_re_ram  : in  std_logic;
		-- Endereço do registrador destino rd da instrução no estágio EX (para detecção load-use).
		i_ex_rd       : in  reg_t;
		-- Indica se a instrução no estágio EX é uma leitura de memória (load).
		i_ex_re_ram   : in  std_logic;
		-- Indica stall global vindo dos estágios posteriores (multdiv, SDRAM ou FENCE.I).
		i_pipe_stall  : in  std_logic;
		-- Habilitação de escrita do PC gerada pela HDU para o estágio IF.
		o_pc_we       : out std_logic;
		-- Habilitação de escrita do registrador IF/ID gerada pela HDU.
		o_ifid_we     : out std_logic;
		-- Bit de validade filtrado (anulado em caso de bolha) para o registrador ID/EX.
		o_idex_valid  : out std_logic;
		-- Índice do registrador fonte rs1 extraído da instrução.
		o_rs1_idx     : out reg_t;
		-- Índice do registrador fonte rs2 extraído da instrução.
		o_rs2_idx     : out reg_t;
		-- Índice do registrador destino rd extraído da instrução.
		o_rd_idx      : out reg_t;
		-- Valor de 32 bits lido da porta rs1 do banco de registradores.
		o_rs1_val     : out word_t;
		-- Valor de 32 bits lido da porta rs2 do banco de registradores.
		o_rs2_val     : out word_t;
		-- Imediato estendido para 32 bits.
		o_imm         : out word_t;
		-- Seletor entre resultado de execução e PC + 4 no estágio EX.
		o_sel_pc4_alu : out std_logic;
		-- Seletor da fonte de Write-Back para o registrador destino.
		o_wb_sel      : out wb_sel_t;
		-- Habilitação de escrita no banco de registradores (filtrada pelo bubble_mux).
		o_we_reg      : out std_logic;
		-- Modo de extensão de leitura da memória de dados.
		o_ext_ram_op  : out ext_ram_op_t;
		-- Seletor entre rs2 ('0') e imediato ('1') para o segundo operando da ULA.
		o_sel_rs2_imm : out std_logic;
		-- Seletor entre PC ('0') e rs1 ('1') para o primeiro operando da ULA.
		o_sel_pc_rs1  : out std_logic;
		-- Código de operação da ULA.
		o_alu_op      : out alu_op_t;
		-- Seleção one-hot do resultado de dados da ULA, decodificada do código de operação.
		o_alu_sel     : out alu_sel_t;
		-- Indica que a instrução pertence à extensão M (multiplicação/divisão).
		o_is_muldiv   : out std_logic;
		-- Indica que a instrução pertence à extensão Zicsr (acesso a registrador CSR).
		o_is_csr      : out std_logic;
		-- Habilitação de escrita na memória de dados (filtrada pelo bubble_mux).
		o_we_ram      : out std_logic;
		-- Habilitação de leitura na memória de dados (filtrada pelo bubble_mux).
		o_re_ram      : out std_logic;
		-- Habilitação geral da memória de dados (filtrada pelo bubble_mux).
		o_en_ram      : out std_logic;
		-- Campo opcode (bits [6:0]) da instrução.
		o_opcode      : out opcode_t;
		-- Campo funct3 (bits [14:12]) da instrução.
		o_funct3      : out funct3_t;
		-- Instrução inexistente em RV32I e fora da extensão M ('1' = ilegal).
		o_illegal     : out std_logic
	);
end entity stage_id;

architecture rtl of stage_id is

	-- Alias para o campo opcode (bits [6:0]) da instrução em IF/ID.
	alias id_opcode        : opcode_t is i_instr(6 downto 0);
	-- Alias para o índice do registrador destino rd (bits [11:7]).
	alias id_rd_idx        : reg_t    is i_instr(11 downto 7);
	-- Alias para o índice do registrador fonte rs1 (bits [19:15]).
	alias id_rs1_idx       : reg_t    is i_instr(19 downto 15);
	-- Alias para o índice do registrador fonte rs2 (bits [24:20]).
	alias id_rs2_idx       : reg_t    is i_instr(24 downto 20);

	-- Operação do extensor de imediato gerada pela unidade de controle base.
	signal cu_ext_imm_op   : ext_imm_op_t;
	-- Código de operação da ULA gerado pela unidade de controle.
	signal cu_alu_op       : alu_op_t;
	-- Operação efetiva do extensor de imediato (forçada para EXT_IMM_I em instruções SYSTEM/CSR).
	signal id_ext_imm_op   : ext_imm_op_t;
	-- Habilitação de escrita em registrador da unidade de controle base RV32I.
	signal base_we_reg     : std_logic;
	-- Habilitação de escrita em registrador do decodificador da extensão M.
	signal m_we_reg        : std_logic;
	-- Habilitação de escrita em registrador do decodificador Zicsr.
	signal csr_we_reg      : std_logic;
	-- Habilitação de escrita em registrador combinada antes do bubble_mux.
	signal cu_we_reg       : std_logic;
	-- Seletor PC/rs1 da unidade de controle base RV32I.
	signal base_sel_pc_rs1 : std_logic;
	-- Seletor PC/rs1 do decodificador da extensão M.
	signal m_sel_pc_rs1    : std_logic;
	-- Indica uso de imediato I-type solicitado por csr_decode.
	signal csr_use_imm_i   : std_logic;
	-- Habilitação de escrita na RAM antes do bubble_mux.
	signal cu_we_ram       : std_logic;
	-- Habilitação de leitura na RAM antes do bubble_mux.
	signal cu_re_ram       : std_logic;
	-- Habilitação geral da RAM antes do bubble_mux.
	signal cu_en_ram       : std_logic;
	-- Seletor de inserção de bolha gerado pela HDU.
	signal id_bubble_sel   : std_logic;
	-- Instrução ilegal segundo o control_unit, antes de a extensão M reivindicá-la.
	signal cu_illegal      : std_logic;
	-- Indica instrução da extensão M decodificada no estágio ID.
	signal id_is_muldiv    : std_logic;
	-- Indica FENCE.I decodificado no estágio ID e legal porque a extensão Zifencei existe.
	signal id_is_fencei    : std_logic;

begin

	o_rs1_idx <= id_rs1_idx;
	o_rs2_idx <= id_rs2_idx;
	o_rd_idx  <= id_rd_idx;

	u_control_unit : entity work.control_unit
		port map (
			i_inst        => i_instr,
			o_sel_pc4_alu => o_sel_pc4_alu,
			o_ext_imm_op  => cu_ext_imm_op,
			o_wb_sel      => o_wb_sel,
			o_we_reg      => base_we_reg,
			o_ext_ram_op  => o_ext_ram_op,
			o_sel_rs2_imm => o_sel_rs2_imm,
			o_sel_pc_rs1  => base_sel_pc_rs1,
			o_alu_op      => cu_alu_op,
			o_we_ram      => cu_we_ram,
			o_re_ram      => cu_re_ram,
			o_en_ram      => cu_en_ram,
			o_opcode      => o_opcode,
			o_funct3      => o_funct3,
			o_illegal     => cu_illegal
		);

	gen_m_decode : if (has_m or has_zmmul) generate
		u_m_decode : entity work.m_decode
			generic map (
				has_div => has_m
			)
			port map (
				i_instr      => i_instr,
				o_is_muldiv  => id_is_muldiv,
				o_we_reg     => m_we_reg,
				o_sel_pc_rs1 => m_sel_pc_rs1
			);
	else generate
		id_is_muldiv <= '0';
		m_we_reg     <= '0';
		m_sel_pc_rs1 <= '0';
	end generate gen_m_decode;

	gen_csr_decode : if has_zicsr generate
		u_csr_decode : entity work.csr_decode
			port map (
				i_instr     => i_instr,
				o_is_csr    => o_is_csr,
				o_we_reg    => csr_we_reg,
				o_use_imm_i => csr_use_imm_i
			);
	else generate
		-- Sem CSRs, SYSTEM ainda carrega o imediato tipo I: o detector de exceções distingue ECALL de EBREAK por ele.
		csr_use_imm_i <= '1' when i_instr(6 downto 0) = OPCODE_SYSTEM else '0';
		o_is_csr      <= '0';
		csr_we_reg    <= '0';
	end generate gen_csr_decode;

	o_is_muldiv   <= id_is_muldiv;
	id_is_fencei  <= '1' when (has_zifencei and id_opcode = OPCODE_MISC_MEM and i_instr(14 downto 12) = FUNCT3_FENCE_I) else '0';
	o_illegal     <= cu_illegal and (not id_is_muldiv) and (not id_is_fencei);
	cu_we_reg     <= base_we_reg     or m_we_reg     or csr_we_reg;
	o_sel_pc_rs1  <= base_sel_pc_rs1 or m_sel_pc_rs1;
	id_ext_imm_op <= EXT_IMM_I when csr_use_imm_i = '1' else cu_ext_imm_op;

	u_extender_imm : entity work.extender_imm
		port map (
			i_instr => i_instr(31 downto 7),
			i_op    => id_ext_imm_op,
			o_imm   => o_imm
		);

	o_alu_op  <= cu_alu_op;
	o_alu_sel <= alu_result_select(cu_alu_op);

	u_regfile : entity work.reg_file
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => i_wb_we,
			i_rs1    => id_rs1_idx,
			i_rs2    => id_rs2_idx,
			i_rd     => i_wb_rd,
			i_d      => i_wb_data,
			o_rs1    => o_rs1_val,
			o_rs2    => o_rs2_val
		);

	u_hdu : entity work.hazard_detection_unit
		port map (
			i_ifid_valid  => i_ifid_valid,
			i_ifid_rs1    => id_rs1_idx,
			i_ifid_rs2    => id_rs2_idx,
			i_ifid_opcode => id_opcode,
			i_idex_rd     => i_ex_rd,
			i_idex_re_ram => i_ex_re_ram,
			i_exmem_rd    => i_mem_rd,
			i_exmem_re_ram => i_mem_re_ram,
			i_stall       => i_pipe_stall,
			o_pc_we       => o_pc_we,
			o_ifid_we     => o_ifid_we,
			o_bubble_sel  => id_bubble_sel
		);

	u_bubble_mux : entity work.bubble_mux
		port map (
			i_sel    => id_bubble_sel,
			i_we_reg => cu_we_reg,
			i_we_ram => cu_we_ram,
			i_re_ram => cu_re_ram,
			i_en_ram => cu_en_ram,
			o_we_reg => o_we_reg,
			o_we_ram => o_we_ram,
			o_re_ram => o_re_ram,
			o_en_ram => o_en_ram
		);

	o_idex_valid <= i_ifid_valid and (not id_bubble_sel);

end architecture rtl;
