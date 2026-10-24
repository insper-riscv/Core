-- =============================================================================
-- Unidade de detecção de exceções síncronas e retorno de trap (MRET)
--
-- Avalia combinacionalmente a instrução presente no estágio EX e sinaliza, no
-- máximo, uma exceção síncrona do modo máquina (o_take = '1') ou o retorno de
-- exceção (o_mret_take = '1') quando a instrução é válida (i_ex_valid = '1') e
-- o pipeline avança (i_run = '1'):
--
--   Código (o_cause) | Exceção                                 | Valor em o_tval
--   -----------------+-----------------------------------------+------------------
--          0         | Alvo de desvio ou salto desalinhado     | i_cf_target
--          2         | Instrução ilegal (SYSTEM/CSR inválida)  | 0x00000000
--          3         | Breakpoint (EBREAK)                     | 0x00000000
--          4         | Endereço de Load desalinhado            | i_ea
--          6         | Endereço de Store desalinhado           | i_ea
--         11         | Chamada de ambiente do modo M (ECALL)   | 0x00000000
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;

entity trap_unit is
	port (
		-- Indica que há uma instrução válida no estágio EX.
		i_ex_valid    : in  std_logic;
		-- Indica que o pipeline está avançando neste ciclo.
		i_run         : in  std_logic;
		-- Campo opcode (bits [6:0]) da instrução no estágio EX.
		i_opcode      : in  opcode_t;
		-- Campo funct3 (bits [14:12]) da instrução no estágio EX.
		i_funct3      : in  funct3_t;
		-- Endereço do registrador destino rd (bits [11:7]) no estágio EX.
		i_rd_idx      : in  reg_t;
		-- Endereço do registrador fonte rs1 (bits [19:15]) no estágio EX.
		i_rs1_idx     : in  reg_t;
		-- Campo imediato de 12 bits (bits [31:20] da instrução) no estágio EX.
		i_imm12       : in  std_logic_vector(11 downto 0);
		-- Endereço efetivo de memória calculado pela ULA no estágio EX.
		i_ea          : in  word_t;
		-- Indica que um desvio condicional, JAL ou JALR foi tomado no estágio EX.
		i_cf_taken    : in  std_logic;
		-- Endereço alvo do desvio ou salto tomado no estágio EX.
		i_cf_target   : in  word_t;
		-- Indica acesso ilegal a registrador CSR sinalizado pelo csr_file.
		i_csr_illegal : in  std_logic;
		-- Pulso que comanda a tomada de trap síncrono no ciclo atual.
		o_take        : out std_logic;
		-- Pulso que comanda o retorno de trap (instrução MRET) no ciclo atual.
		o_mret_take   : out std_logic;
		-- Código da causa da exceção síncrona detectada (para gravação em mcause).
		o_cause       : out word_t;
		-- Valor adicional associado à exceção (endereço faltante ou zero, para gravação em mtval).
		o_tval        : out word_t
	);
end entity trap_unit;

architecture rtl of trap_unit is

	-- Campo funct12 da instrução ECALL (0x000).
	constant IMM12_ECALL          : std_logic_vector(11 downto 0) := x"000";
	-- Campo funct12 da instrução EBREAK (0x001).
	constant IMM12_EBREAK         : std_logic_vector(11 downto 0) := x"001";
	-- Campo funct12 da instrução WFI (0x105).
	constant IMM12_WFI            : std_logic_vector(11 downto 0) := x"105";
	-- Campo funct12 da instrução MRET (0x302).
	constant IMM12_MRET           : std_logic_vector(11 downto 0) := x"302";

	-- Código mcause para endereço de instrução desalinhado (0).
	constant CAUSE_MISALIGNED_PC  : word_t := x"00000000";
	-- Código mcause para instrução ilegal (2).
	constant CAUSE_ILLEGAL_INSTR  : word_t := x"00000002";
	-- Código mcause para breakpoint EBREAK (3).
	constant CAUSE_BREAKPOINT     : word_t := x"00000003";
	-- Código mcause para endereço de load desalinhado (4).
	constant CAUSE_MISALIGNED_LD  : word_t := x"00000004";
	-- Código mcause para endereço de store desalinhado (6).
	constant CAUSE_MISALIGNED_ST  : word_t := x"00000006";
	-- Código mcause para chamada de ambiente do modo M - ECALL (11).
	constant CAUSE_MACHINE_ECALL  : word_t := x"0000000B";

	-- Indica que a instrução pertence à classe SYSTEM (opcode 1110011).
	signal is_system   : std_logic;
	-- Indica que a instrução SYSTEM é uma operação de acesso a CSR.
	signal is_csr      : std_logic;
	-- Indica que funct3 = "000", rd = x0 e rs1 = x0 (formato exigido por ECALL/EBREAK/MRET/WFI).
	signal no_regs     : std_logic;
	-- Indica decodificação da instrução ECALL.
	signal is_ecall    : std_logic;
	-- Indica decodificação da instrução EBREAK.
	signal is_ebreak   : std_logic;
	-- Indica decodificação da instrução MRET.
	signal is_mret     : std_logic;
	-- Indica decodificação da instrução WFI.
	signal is_wfi      : std_logic;

	-- Indica instrução da classe SYSTEM com codificação não suportada/ilegal.
	signal sys_illegal : std_logic;
	-- Indica instrução de leitura de memória (LOAD) com endereço desalinhado.
	signal ld_misal    : std_logic;
	-- Indica instrução de escrita em memória (STORE) com endereço desalinhado.
	signal st_misal    : std_logic;
	-- Indica desvio ou salto tomado para endereço alvo não alinhado a 4 bytes.
	signal cf_misal    : std_logic;

	-- Sinal agregador que indica ocorrência de qualquer exceção síncrona na instrução atual.
	signal has_exc     : std_logic;

begin

	is_system <= '1' when i_opcode = OPCODE_SYSTEM else '0';
	is_csr    <= '1' when (is_system = '1' and i_funct3 /= FUNCT3_PRIV and i_funct3 /= "100") else '0';
	no_regs   <= '1' when (i_funct3 = FUNCT3_PRIV and i_rd_idx = REG_ZERO and i_rs1_idx = REG_ZERO) else '0';

	is_ecall  <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_ECALL)  else '0';
	is_ebreak <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_EBREAK) else '0';
	is_mret   <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_MRET)   else '0';
	is_wfi    <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_WFI)    else '0';

	sys_illegal <= '1' when (is_system = '1' and is_csr = '0' and
	                         is_ecall = '0' and is_ebreak = '0' and
	                         is_mret = '0' and is_wfi = '0')
	                   else '0';

	ld_misal <= '1' when (i_opcode = OPCODE_LOAD and
	                      ((i_funct3 = FUNCT3_LW and i_ea(1 downto 0) /= "00") or
	                       ((i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU) and i_ea(0) = '1')))
	                else '0';

	st_misal <= '1' when (i_opcode = OPCODE_STORE and
	                      ((i_funct3 = FUNCT3_SW and i_ea(1 downto 0) /= "00") or
	                       (i_funct3 = FUNCT3_SH and i_ea(0) = '1')))
	                else '0';

	cf_misal <= '1' when (i_cf_taken = '1' and i_cf_target(1 downto 0) /= "00") else '0';

	has_exc <= cf_misal or sys_illegal or (is_csr and i_csr_illegal) or is_ebreak or
	           ld_misal or st_misal or is_ecall;

	o_take      <= has_exc and i_ex_valid and i_run;
	o_mret_take <= is_mret and i_ex_valid and i_run;

	o_cause <= CAUSE_MISALIGNED_PC when cf_misal = '1' else
	           CAUSE_ILLEGAL_INSTR when (sys_illegal = '1' or (is_csr = '1' and i_csr_illegal = '1')) else
	           CAUSE_BREAKPOINT    when is_ebreak = '1' else
	           CAUSE_MISALIGNED_LD when ld_misal = '1' else
	           CAUSE_MISALIGNED_ST when st_misal = '1' else
	           CAUSE_MACHINE_ECALL;

	o_tval  <= i_cf_target when cf_misal = '1' else
	           i_ea        when (ld_misal = '1' or st_misal = '1') else
	           (others => '0');

end architecture rtl;
