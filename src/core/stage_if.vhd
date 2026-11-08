-- =============================================================================
-- Estágio IF (Instruction Fetch) do Pipeline RV32
--
-- Encapsula a lógica de busca de instruções do primeiro estágio do pipeline:
--   1. Seleção da fonte do próximo PC (PC + 4, alvo de branch/JAL, alvo de JALR
--      ou endereço de redirecionamento de trap/MRET/FENCE.I).
--   2. Instanciação da unidade pc_fetch (registrador de PC e somador PC + 4).
--   3. Decodificação combinacional do espaço de endereços de código entre
--      BOOT_MEMORY, FLASH e cache de instruções externa (SDRAM) usando as
--      constantes centralizadas em mem_map_consts.
--   4. Controle de espera da cache de instruções (if_wait) e invalidação por
--      instrução FENCE.I (o_ic_inval).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.pc_src_consts.all;
use work.mem_map_consts.all;

entity stage_if is
	generic (
		-- Expoente do tamanho da BOOT_MEMORY: ela ocupa os endereços [0, 2**boot_memory_bits).
		boot_memory_bits : natural := 12;
		-- Fim exclusivo, em KiB, da ROM, que começa logo depois da BOOT_MEMORY.
		rom_end_kib   : natural := 32;
		-- A ROM é externa quando é alcançada pela porta do núcleo (o_ext_* ou a porta de instruções): a instrução sai pela porta de instruções e o dado pela porta externa, e a memória por trás pode ser externa ao chip ou uma memória interna atrás de cache.
		rom_external  : boolean := false;
		-- Base, em KiB, da RAM.
		ram_base_kib  : natural := 32;
		-- Fim exclusivo, em KiB, da RAM.
		ram_end_kib   : natural := 1048576;
		-- A RAM é externa quando é alcançada pela porta do núcleo (o_ext_*): o dado sai pela porta externa, e a memória por trás pode ser externa ao chip ou uma memória interna atrás de cache.
		ram_external  : boolean := false;
		-- Base, em KiB, da janela externa: todo endereço a partir dela sai pela porta externa.
		ext_base_kib  : natural := 1048576
	);
	port (
		-- Sinal de clock principal do processador.
		i_clk             : in  std_logic;
		-- Sinal de reset ativo em '1'.
		i_rst             : in  std_logic;
		-- Habilitação de escrita do PC vinda da unidade de detecção de hazards (HDU).
		i_hdu_pc_we       : in  std_logic;
		-- Indica que os estágios iniciais do pipeline estão aptos a avançar neste ciclo.
		i_pipe_run        : in  std_logic;
		-- Indica desvio condicional tomado ou salto JAL decidido no estágio EX.
		i_ex_branch_taken : in  std_logic;
		-- Indica salto indireto JALR decidido no estágio EX.
		i_ex_jalr_taken   : in  std_logic;
		-- Indica tomada de exceção síncrona decidida no estágio EX.
		i_trap_take       : in  std_logic;
		-- Indica retorno de exceção (MRET) decidido no estágio EX.
		i_mret_take       : in  std_logic;
		-- Indica conclusão de instrução FENCE.I decidida no estágio EX.
		i_fencei_take     : in  std_logic;
		-- Pulso de invalidação da cache de instruções (conclusão de FENCE.I, mesmo que descartada em EX).
		i_ic_inval        : in  std_logic;
		-- O registrador IF/ID carrega neste ciclo.
		i_ifid_en         : in  std_logic;
		-- O registrador IF/ID é limpo neste ciclo.
		i_flush_if_id     : in  std_logic;
		-- PC da instrução que está em IF/ID (endereço a repetir se a cache não a tinha).
		i_ifid_pc         : in  word_t;
		-- Endereço alvo calculado no estágio EX para branch condicional ou JAL.
		i_branch_target   : in  word_t;
		-- Endereço alvo calculado no estágio EX para salto indireto JALR.
		i_jalr_target     : in  word_t;
		-- Endereço de redirecionamento prioritário (mtvec, mepc ou PC + 4 pós-FENCE.I).
		i_redirect_pc     : in  word_t;
		-- Palavra de instrução retornada pela memória BOOT_MEMORY.
		i_boot_memory_data   : in  word_t;
		-- Palavra de instrução retornada pela memória FLASH (porta 1).
		i_flash_data      : in  word_t;
		-- Palavra de instrução retornada pela cache de instruções externa (SDRAM).
		i_ic_data         : in  word_t;
		-- Indica que a cache de instruções externa possui a palavra válida para o PC atual.
		i_ic_ready        : in  std_logic;
		-- Endereço atual do Program Counter (enviado ao registrador IF/ID).
		o_pc              : out word_t;
		-- Valor de PC + 4 calculado (enviado ao registrador IF/ID).
		o_pc4             : out word_t;
		-- Instrução de 32 bits selecionada (enviada ao registrador IF/ID).
		o_instr           : out word_t;
		-- Indica que a instrução entregue em o_instr é válida (não está em espera de I-cache).
		o_instr_valid     : out std_logic;
		-- Endereço de busca enviado às memórias de instrução externas.
		o_if_addr         : out word_t;
		-- Habilitação de leitura das memórias de instrução externas.
		o_if_rden         : out std_logic;
		-- Indica que o endereço de busca pertence à região atendida pela I-cache (SDRAM).
		o_ic_sel          : out std_logic;
		-- Pulso que comanda a invalidação da cache de instruções externa (FENCE.I).
		o_ic_inval        : out std_logic;
		-- Repete a busca da instrução de IF/ID, que a cache de instruções não tinha: o PC volta a ela e IF/ID é limpo.
		o_replay          : out std_logic
	);
end entity stage_if;

architecture rtl of stage_if is

	-- Valor atual do PC lido internamente para decodificação de região de memória.
	signal if_pc          : word_t;
	-- Seletor de 2 bits da fonte do próximo PC (PC_SRC_*).
	signal pc_src         : pc_src_t;
	-- Habilitação efetiva de escrita no registrador PC.
	signal pc_write_en    : std_logic;
	-- Indica que o endereço atual do PC aponta para a BOOT_MEMORY.
	signal is_boot_memory_if : std_logic;
	-- Indica que o endereço atual do PC aponta para a região de SDRAM.
	signal if_in_sdram    : std_logic;
	-- Indica que a busca na região de SDRAM está aguardando resposta da I-cache.
	signal if_wait        : std_logic;
	-- A instrução carregada em IF/ID veio sem resposta da I-cache e tem de ser buscada de novo.
	signal miss_q         : std_logic := '0';
	-- Repetição da busca neste ciclo.
	signal replay         : std_logic;

begin

	-- Seleção prioritária da fonte do próximo PC.
	pc_src <= PC_SRC_REDIRECT when (i_trap_take = '1' or i_mret_take = '1' or i_fencei_take = '1') else
	          PC_SRC_JALR     when i_ex_jalr_taken   = '1' else
	          PC_SRC_BRANCH   when i_ex_branch_taken = '1' else
	          PC_SRC_PC4;

	-- O PC avança quando liberado pela HDU e sem espera de I-cache, ou imediatamente em redirecionamentos.
	-- O PC avança sem esperar a I-cache: a resposta tardia (i_ic_ready) só marca a instrução de IF/ID como sem resposta, e o
	-- PC volta a ela no ciclo seguinte (replay). Assim a saída das RAMs da cache chega só a dois registradores.
	pc_write_en <= i_hdu_pc_we or
	               (((i_ex_branch_taken or i_ex_jalr_taken) and i_pipe_run) or
	                i_trap_take or i_mret_take or i_fencei_take);

	replay <= miss_q and i_hdu_pc_we;
	o_replay <= replay;

	process (i_clk)
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' or i_flush_if_id = '1' then
				miss_q <= '0';
			elsif i_ifid_en = '1' then
				miss_q <= if_wait;
			end if;
		end if;
	end process;

	u_pc_fetch : entity work.pc_fetch
		port map (
			i_clk           => i_clk,
			i_rst           => i_rst,
			i_pc_we         => pc_write_en,
			i_pc_src        => pc_src,
			i_branch_target => i_branch_target,
			i_jalr_target   => i_jalr_target,
			i_redirect_pc   => i_redirect_pc,
			i_replay        => replay,
			i_replay_pc     => i_ifid_pc,
			o_pc            => if_pc,
			o_pc4           => o_pc4
		);

	is_boot_memory_if <= '1' when unsigned(if_pc) < boot_memory_end(boot_memory_bits) else '0';
	if_in_sdram    <= '1' when (is_boot_memory_if = '0' and
	                            is_external_addr(unsigned(if_pc), rom_end_kib, rom_external, ram_base_kib, ram_end_kib, ram_external, ext_base_kib)) else '0';
	if_wait        <= if_in_sdram and (not i_ic_ready);

	o_instr <= i_boot_memory_data when is_boot_memory_if = '1' else
	           i_ic_data       when (if_in_sdram = '1' or rom_external) else
	           i_flash_data;

	o_pc          <= if_pc;
	o_if_addr     <= if_pc;
	o_if_rden     <= '1';
	o_instr_valid <= not if_wait;
	o_ic_sel      <= if_in_sdram;
	o_ic_inval    <= i_ic_inval;

end architecture rtl;
