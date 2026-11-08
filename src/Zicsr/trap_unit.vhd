-- =============================================================================
-- Unidade de detecção de exceções síncronas e retorno de trap (MRET)
--
-- Avalia combinacionalmente a instrução presente no estágio EX e sinaliza, no
-- máximo, uma exceção síncrona do modo máquina (o_take = '1') ou o retorno de
-- exceção (o_mret_take = '1') quando a instrução é válida (i_ex_valid = '1') e
-- o pipeline avança (i_run = '1'). Uma interrupção a tomar (i_irq_take = '1')
-- tem prioridade sobre qualquer exceção e sobre o MRET da instrução em EX: a
-- instrução é abortada (o_take = '1', o_irq = '1', causa de i_irq_cause e
-- mtval zero) e o mepc recebe o endereço dela, a primeira que não completou.
-- A única instrução que não é abortada é FENCE.I, que redireciona o pipeline
-- para a instrução seguinte; a interrupção espera um ciclo por ela.
--
--   Código (o_cause) | Exceção                                 | Valor em o_tval
--   -----------------+-----------------------------------------+------------------
--          0         | Alvo de desvio ou salto desalinhado     | i_cf_target
--          2         | Instrução ilegal (qualquer encoding     | 0x00000000
--                    | inexistente, SYSTEM ou CSR inválido)    |
--          3         | Breakpoint (EBREAK)                     | 0x00000000
--          4         | Endereço de Load desalinhado que o      | i_ea
--                    | hardware não executa                    |
--          6         | Endereço de Store desalinhado que o     | i_ea
--                    | hardware não executa                    |
--         11         | Chamada de ambiente do modo M (ECALL)   | 0x00000000
--          1         | Falha de acesso de instrução (busca fora   | i_pc
--                    | de região executável, com has_access_faults)|
--          5         | Falha de acesso de load (endereço fora do  | i_ea
--                    | mapa válido, com has_access_faults)        |
--          7         | Falha de acesso de store (fora do mapa ou  | i_ea
--                    | em região só de leitura)                   |
--   0x80000003, 7, B | Interrupção de software, timer, externa | 0x00000000
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.byte_mask_consts.all;
use work.opcode_consts.all;
use work.funct3_consts.all;
use work.mem_map_consts.all;
use work.trap_consts.all;

entity trap_unit is
	generic (
		-- Executa em hardware o acesso desalinhado à memória principal (extensão Zicclsm); '0' faz todo desalinhado gerar trap.
		has_zicclsm     : boolean := true;
		-- Confere o endereço efetivo de loads e stores (causas 4 e 6); '0' ignora i_ea, para a instância que não o conhece.
		check_ea        : boolean := true;
		-- Expoente do tamanho da BOOT_MEMORY: ela ocupa os endereços [0, 2**boot_memory_bits).
		boot_memory_bits   : natural := 12;
		-- Fim exclusivo, em KiB, da ROM, que começa logo depois da BOOT_MEMORY.
		-- Endereço no mapa do Core (platform.yaml); as caches do Memory usam o da região da FLASH.
		rom_end_kib     : natural := 32;
		-- A ROM é externa quando é alcançada pela porta do núcleo (o_ext_* ou a porta de instruções): a instrução sai pela porta de instruções e o dado pela porta externa, e a memória por trás pode ser externa ao chip ou uma memória interna atrás de cache.
		rom_external    : boolean := false;
		-- Base, em KiB, da RAM.
		-- Endereço no mapa do Core (platform.yaml); as caches do Memory usam o da região da FLASH.
		ram_base_kib    : natural := 32;
		-- Fim exclusivo, em KiB, da RAM.
		-- Endereço no mapa do Core (platform.yaml); as caches do Memory usam o da região da FLASH.
		ram_end_kib     : natural := 1048576;
		-- A RAM é externa quando é alcançada pela porta do núcleo (o_ext_*): o dado sai pela porta externa, e a memória por trás pode ser externa ao chip ou uma memória interna atrás de cache.
		ram_external    : boolean := false;
		-- Base, em KiB, da janela externa: todo endereço a partir dela sai pela porta externa.
		-- Endereço no mapa do Core (platform.yaml); as caches do Memory usam o da região da FLASH.
		ext_base_kib    : natural := 1048576;
		-- Base, em KiB, da janela de periféricos: o fim da memória principal que o desalinhamento em hardware atende.
		-- Endereço no mapa do Core (platform.yaml); as caches do Memory usam o da região da FLASH.
		periph_base_kib : natural := 2097152;
		-- A classificação do endereço efetivo (memória principal e mesma região das duas palavras) vem registrada pelas portas i_ea_main e i_ea_same_region, em vez de ser decodificada de i_ea.
		ea_flags_external : boolean := false;
		-- Gera as falhas de acesso 1 (busca), 5 (load) e 7 (store) a partir de i_fetch_ok, i_ea_rd_ok e i_ea_wr_ok; a de dados exige check_ea.
		has_access_faults : boolean := false
	);
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
		-- O endereço efetivo está na memória principal (com ea_flags_external).
		i_ea_main        : in  std_logic := '0';
		-- As duas palavras de um acesso que cruza estão na mesma região da memória principal (com ea_flags_external).
		i_ea_same_region : in  std_logic := '0';
		-- A busca da instrução em EX veio de região executável do mapa ('0' gera a causa 1 com has_access_faults).
		i_fetch_ok    : in  std_logic := '1';
		-- PC da instrução em EX (mtval da falha de acesso de instrução).
		i_pc          : in  word_t    := (others => '0');
		-- O endereço efetivo aceita leitura no mapa (um load com '0' gera a causa 5 com has_access_faults).
		i_ea_rd_ok    : in  std_logic := '1';
		-- O endereço efetivo aceita escrita no mapa (um store com '0' gera a causa 7 com has_access_faults).
		i_ea_wr_ok    : in  std_logic := '1';
		-- Indica que um desvio condicional, JAL ou JALR foi tomado no estágio EX.
		i_cf_taken    : in  std_logic;
		-- Endereço alvo do desvio ou salto tomado no estágio EX.
		i_cf_target   : in  word_t;
		-- Indica acesso ilegal a registrador CSR sinalizado pelo csr_file.
		i_csr_illegal : in  std_logic;
		-- Instrução inexistente apontada pela decodificação no estágio ID ('1' = ilegal).
		i_illegal     : in  std_logic := '0';
		-- Há interrupção a tomar: pendente, habilitada em mie e com mstatus.MIE em '1' (do csr_file).
		i_irq_take    : in  std_logic := '0';
		-- Código de mcause da interrupção a tomar (bit 31 em '1').
		i_irq_cause   : in  word_t    := (others => '0');
		-- Pulso que comanda a tomada de trap síncrono no ciclo atual.
		o_take        : out std_logic;
		-- Pulso que comanda o retorno de trap (instrução MRET) no ciclo atual.
		o_mret_take   : out std_logic;
		-- A tomada comandada por o_take é a de uma interrupção, e não a de uma exceção síncrona.
		o_irq         : out std_logic;
		-- Código da causa da exceção síncrona detectada (para gravação em mcause).
		o_cause       : out word_t;
		-- Valor adicional associado à exceção (endereço faltante ou zero, para gravação em mtval).
		o_tval        : out word_t
	);
end entity trap_unit;

architecture rtl of trap_unit is

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
	-- Indica instrução de leitura de memória (LOAD) com endereço desalinhado, já descontados os casos que o hardware executa.
	signal ld_misal    : std_logic;
	-- Indica instrução de escrita em memória (STORE) com endereço desalinhado, já descontados os casos que o hardware executa.
	signal st_misal    : std_logic;
	-- Indica LOAD com endereço desalinhado, executado ou não pelo hardware.
	signal ld_unaligned : std_logic;
	-- Indica STORE com endereço desalinhado, executado ou não pelo hardware.
	signal st_unaligned : std_logic;
	-- Indica que o endereço efetivo está na memória principal (RAM interna ou SDRAM): fora da flash e da janela de periféricos.
	signal in_main_mem : std_logic;
	-- Indica que o acesso desalinhado cabe numa única palavra (LH, LHU ou SH com offset 1) e o hardware o executa.
	signal misal_in_word : std_logic;
	-- Indica acesso que ocupa duas palavras (LW e SW fora do offset 0, LH, LHU e SH no offset 3).
	signal crosses_word : std_logic;
	-- Indica que o endereço efetivo está na última palavra de uma região de 1 GiB (bits [29:2] todos em '1'): a palavra seguinte pertence à outra região.
	signal last_word    : std_logic;
	-- Indica que as duas palavras de um acesso que cruza estão na mesma região da memória principal (RAM interna ou SDRAM).
	signal same_region  : std_logic;
	-- Indica acesso desalinhado que o hardware executa (dentro da palavra ou cruzando, na memória principal).
	signal misal_exec   : std_logic;
	-- Indica desvio ou salto tomado para endereço alvo não alinhado a 4 bytes.
	signal cf_misal    : std_logic;
	-- Indica busca de instrução fora de região executável.
	signal fetch_fault : std_logic;
	-- Indica load para endereço que o mapa não aceita ler.
	signal ld_fault    : std_logic;
	-- Indica store para endereço que o mapa não aceita escrever.
	signal st_fault    : std_logic;
	-- Indica instrução ilegal por qualquer motivo (codificação inexistente, SYSTEM inválida ou CSR inválido), que tem prioridade sobre o alvo desalinhado.
	signal any_illegal : std_logic;

	-- Sinal agregador que indica ocorrência de qualquer exceção síncrona na instrução atual.
	signal has_exc     : std_logic;
	-- Indica decodificação da instrução FENCE.I, que redireciona o pipeline e por isso não é abortada.
	signal is_fencei   : std_logic;
	-- Indica que a interrupção a tomar é tomada neste ciclo: a instrução em EX é válida, avança e não é FENCE.I.
	signal irq_go      : std_logic;

begin

	is_system <= '1' when i_opcode = OPCODE_SYSTEM else '0';
	is_csr    <= '1' when (is_system = '1' and i_funct3 /= FUNCT3_PRIV and i_funct3 /= FUNCT3_SYSTEM_RESERVED) else '0';
	no_regs   <= '1' when (i_funct3 = FUNCT3_PRIV and i_rd_idx = REG_ZERO and i_rs1_idx = REG_ZERO) else '0';

	is_ecall  <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_ECALL)  else '0';
	is_ebreak <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_EBREAK) else '0';
	is_mret   <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_MRET)   else '0';
	is_wfi    <= '1' when (is_system = '1' and no_regs = '1' and i_imm12 = IMM12_WFI)    else '0';

	sys_illegal <= '1' when (is_system = '1' and is_csr = '0' and
	                         is_ecall = '0' and is_ebreak = '0' and
	                         is_mret = '0' and is_wfi = '0')
	                   else '0';

	ld_unaligned <= '1' when (i_opcode = OPCODE_LOAD and
	                          ((i_funct3 = FUNCT3_LW and i_ea(1 downto 0) /= BYTE_OFFSET_0) or
	                           ((i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU) and i_ea(0) = '1')))
	                    else '0';

	st_unaligned <= '1' when (i_opcode = OPCODE_STORE and
	                          ((i_funct3 = FUNCT3_SW and i_ea(1 downto 0) /= BYTE_OFFSET_0) or
	                           (i_funct3 = FUNCT3_SH and i_ea(0) = '1')))
	                    else '0';

	-- A memória principal vai do fim da ROM interna (ou da base externa) até a janela de periféricos; as bases
	-- constantes de potência de 2 viram testes de bits na síntese.
	in_main_mem <= i_ea_main when ea_flags_external else
	               '1' when (unsigned(i_ea) >= main_mem_base(rom_end_kib, ext_base_kib, rom_external, boot_memory_bits) and
	                         unsigned(i_ea) < kib_to_addr(periph_base_kib))
	               else '0';

	misal_in_word <= '1' when (has_zicclsm and in_main_mem = '1' and i_ea(1 downto 0) = BYTE_OFFSET_1 and
	                           (i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU or i_funct3 = FUNCT3_SH))
	                 else '0';

	crosses_word <= '1' when ((i_funct3 = FUNCT3_LW or i_funct3 = FUNCT3_SW) and i_ea(1 downto 0) /= BYTE_OFFSET_0) or
	                         ((i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU or i_funct3 = FUNCT3_SH) and i_ea(1 downto 0) = BYTE_OFFSET_3)
	                else '0';

	last_word <= '1' when is_last_word(unsigned(i_ea), rom_end_kib, ram_base_kib, ram_end_kib, ext_base_kib, periph_base_kib)
	             else '0';

	-- As duas palavras de um acesso que cruza ficam na mesma região quando o endereço está na memória principal
	-- e não na última palavra da região, pois a palavra seguinte pertenceria à região vizinha.
	same_region <= i_ea_same_region when ea_flags_external else (in_main_mem and (not last_word));

	misal_exec <= '1' when (misal_in_word = '1' or
	                        (has_zicclsm and crosses_word = '1' and same_region = '1' and
	                         (i_opcode = OPCODE_LOAD or i_opcode = OPCODE_STORE)))
	              else '0';

	ld_misal <= ld_unaligned and (not misal_exec) when check_ea else '0';
	st_misal <= st_unaligned and (not misal_exec) when check_ea else '0';

	-- O desalinhamento que o hardware não executa vem antes da falha de acesso (a ordem opcional da Tabela 17 do manual,
	-- que mantém a causa 4 ou 6 do acesso desalinhado fora da memória principal); o desalinhamento que ele executa
	-- só passa se o endereço for válido, e a falha é do endereço da primeira palavra.
	ld_fault <= '1' when (has_access_faults and check_ea and i_opcode = OPCODE_LOAD and i_ea_rd_ok = '0' and ld_misal = '0') else '0';
	st_fault <= '1' when (has_access_faults and check_ea and i_opcode = OPCODE_STORE and i_ea_wr_ok = '0' and st_misal = '0') else '0';
	fetch_fault <= '1' when (has_access_faults and i_fetch_ok = '0') else '0';

	any_illegal <= i_illegal or sys_illegal or (is_csr and i_csr_illegal);

	-- Um salto ou desvio de codificação reservada é ilegal (causa 2), e a Tabela 17 do manual privilegiado põe a
	-- instrução ilegal acima do endereço de instrução desalinhado (causa 0): só o salto legal gera a causa 0. Só a
	-- ilegalidade da decodificação importa aqui, porque as instruções SYSTEM nunca tomam desvio.
	cf_misal <= '1' when (i_cf_taken = '1' and i_cf_target(1 downto 0) /= BYTE_OFFSET_0 and i_illegal = '0') else '0';

	has_exc <= fetch_fault or cf_misal or any_illegal or is_ebreak or
	           ld_misal or st_misal or ld_fault or st_fault or is_ecall;

	is_fencei <= '1' when (i_opcode = OPCODE_MISC_MEM and i_funct3 = FUNCT3_FENCE_I) else '0';
	irq_go    <= i_irq_take and i_ex_valid and i_run and (not is_fencei);

	o_take      <= (has_exc and i_ex_valid and i_run) or irq_go;
	o_mret_take <= is_mret and i_ex_valid and i_run and (not irq_go);
	o_irq       <= irq_go;

	o_cause <= i_irq_cause when irq_go = '1' else
	           CAUSE_FETCH_FAULT   when fetch_fault = '1' else
	           CAUSE_ILLEGAL_INSTR when any_illegal = '1' else
	           CAUSE_MISALIGNED_PC when cf_misal = '1' else
	           CAUSE_BREAKPOINT    when is_ebreak = '1' else
	           CAUSE_MISALIGNED_LD when ld_misal = '1' else
	           CAUSE_MISALIGNED_ST when st_misal = '1' else
	           CAUSE_LOAD_FAULT    when ld_fault = '1' else
	           CAUSE_STORE_FAULT   when st_fault = '1' else
	           CAUSE_MACHINE_ECALL;

	o_tval  <= (others => '0') when irq_go = '1' else
	           i_pc        when fetch_fault = '1' else
	           i_cf_target when cf_misal = '1' else
	           i_ea        when ((ld_misal = '1' or st_misal = '1' or ld_fault = '1' or st_fault = '1') and i_illegal = '0') else
	           (others => '0');

end architecture rtl;
