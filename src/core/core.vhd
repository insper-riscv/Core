-- =============================================================================
-- Topo Estrutural do Processador RISC-V RV32 em Pipeline de 5 Estágios (core)
--
-- Conecta estruturalmente os 5 estágios do pipeline e seus 4 registradores de
-- barreira temporal:
--   stage_if -> reg_if_id -> stage_id -> reg_id_ex -> stage_ex ->
--   reg_ex_mem -> stage_mem -> reg_mem_wb -> stage_wb
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.fwd_consts.all;

entity core is
	generic (
		-- Habilita a extensão M de multiplicação e divisão inteira.
		has_m        : boolean := false;
		-- Habilita só a multiplicação (extensão Zmmul), sem divisão; has_m já a inclui.
		has_zmmul    : boolean := false;
		-- Habilita a extensão Zicsr e o tratamento de exceções do modo máquina.
		has_zicsr    : boolean := false;
		-- Habilita os contadores da extensão Zicntr (mcycle, minstret, time); exige has_zicsr.
		has_zicntr   : boolean := false;
		-- Ciclos de clock do core por tick do contador time (50 dá 1 MHz a 50 MHz).
		tick_cycles  : positive := 50;
		-- Habilita a extensão Zifencei para sincronização da cache de instruções.
		has_zifencei : boolean := false;
		-- Executa em hardware o acesso desalinhado à memória principal (extensão Zicclsm).
		has_zicclsm  : boolean := true;
		-- Habilita o handshake de flush da cache de dados write-back durante FENCE.I.
		has_dcache   : boolean := false;
		-- Mapa da plataforma sdram: a FLASH fica fora do núcleo (0x20000000) e, com a SDRAM, sai pela porta externa; não há RAM interna.
		ext_flash    : boolean := false;
		-- Habilita a extensão Zihpm com os quatro contadores de eventos (índices 3 a 6); é o token da matriz de perfis. Exige has_zicsr.
		has_zihpm    : boolean := false;
		-- Quantidade de contadores de eventos da extensão Zihpm (0 = sem Zihpm, salvo has_zihpm); exige has_zicsr.
		hpm_counters : natural range 0 to 4 := 0
	);
	port (
		-- Sinal de clock principal do processador.
		i_clk           : in  std_logic;
		-- Sinal de reset ativo em '1': assíncrono nos registradores de uso geral, síncrono nos de pipeline.
		i_rst           : in  std_logic;

		-- Endereço de busca de instrução (PC atual no estágio IF).
		o_if_addr       : out word_t;
		-- Habilitação de leitura da memória de instruções no estágio IF.
		o_if_rden       : out std_logic;
		-- Palavra de instrução retornada pela BOOT_ROM.
		i_boot_rom_data : in  word_t;
		-- Palavra de instrução retornada pela memória FLASH (porta 1).
		i_flash_data    : in  word_t;

		-- Endereço de leitura de dados na segunda porta da memória FLASH (estágio MEM).
		o_flash_addr2   : out word_t;
		-- Habilitação de leitura de dados na segunda porta da memória FLASH (estágio MEM).
		o_flash_rden2   : out std_logic;
		-- Palavra de dados lida da segunda porta da memória FLASH (recebida no estágio WB).
		i_flash_data2   : in  word_t;

		-- Endereço de acesso à memória RAM interna de dados (estágio MEM).
		o_ram_addr      : out word_t;
		-- Palavra de dados alinhada para escrita na RAM interna (estágio MEM).
		o_ram_wdata     : out word_t;
		-- Palavra de dados lida da RAM interna (recebida no estágio WB).
		i_ram_rdata     : in  word_t;
		-- Habilitação geral da memória RAM interna (estágio MEM).
		o_ram_en        : out std_logic;
		-- Habilitação de escrita na memória RAM interna (estágio MEM).
		o_ram_wren      : out std_logic;
		-- Habilitação de leitura na memória RAM interna (estágio MEM).
		o_ram_rden      : out std_logic;
		-- Máscara de habilitação de escrita por byte na RAM interna (estágio MEM).
		o_ram_byteena   : out byte_mask_t;

		-- Endereço de acesso ao barramento externo de dados SDRAM/periféricos (estágio MEM).
		o_sdram_addr    : out word_t;
		-- Palavra de dados alinhada para escrita no barramento externo SDRAM (estágio MEM).
		o_sdram_wdata   : out word_t;
		-- Máscara de habilitação de bytes no barramento externo SDRAM (estágio MEM).
		o_sdram_byteena : out byte_mask_t;
		-- Habilitação de leitura no barramento externo SDRAM (estágio MEM).
		o_sdram_rden    : out std_logic;
		-- Habilitação de escrita no barramento externo SDRAM (estágio MEM).
		o_sdram_wren    : out std_logic;
		-- Palavra de dados lida do barramento externo SDRAM.
		i_sdram_rdata   : in  word_t    := (others => '0');
		-- Sinaliza que o escravo externo SDRAM concluiu a transação atual.
		i_sdram_ready   : in  std_logic := '1';
		-- Indica ao escravo externo SDRAM que o estágio MEM avançou neste ciclo.
		o_mem_advance   : out std_logic;

		-- Palavra de instrução fornecida pela cache de instruções externa (região SDRAM).
		i_ic_data       : in  word_t    := (others => '0');
		-- Indica que a cache de instruções externa possui a instrução válida para o PC atual.
		i_ic_ready      : in  std_logic := '1';
		-- Indica que o endereço de busca atual (o_if_addr) pertence à região de SDRAM.
		o_ic_sel        : out std_logic;
		-- Pulso que comanda a invalidação da cache de instruções externa (instrução FENCE.I).
		o_ic_inval      : out std_logic;

		-- Pulso que requisita o flush da cache de dados write-back (instrução FENCE.I).
		o_dc_flush      : out std_logic;
		-- Pulso de confirmação de término do flush da cache de dados write-back.
		i_dc_done       : in  std_logic := '0';

		-- Pulso de um ciclo: uma exceção ocorreu e o core não tem CSRs para registrá-la (só existe sem Zicsr; '0' com Zicsr).
		o_trap          : out std_logic;
		-- Código de causa da exceção sinalizada, no formato do mcause (zero com Zicsr).
		o_trap_cause    : out word_t;
		-- PC da instrução que gerou a exceção sinalizada (zero com Zicsr).
		o_trap_pc       : out word_t;
		-- Pulso de um ciclo: uma instrução foi retirada em EX (válida, com o pipeline andando e sem exceção).
		o_retire        : out std_logic;
		-- Eventos das caches e da FLASH para os contadores do Zihpm: bit 0 falha da cache de instruções (evento 5),
		-- bit 1 falha da cache de dados (6), bit 2 ciclo de espera por FLASH (7); pulsos de um ciclo.
		i_hpm_ext_events : in  std_logic_vector(2 downto 0) := (others => '0')
	);
end entity core;

architecture rtl of core is

	-- Quantidade efetiva de contadores de eventos: os pedidos em hpm_counters ou, com has_zihpm, os quatro.
	function effective_hpm_count return natural is
	begin
		if hpm_counters > 0 then
			return hpm_counters;
		elsif has_zihpm then
			return 4;
		end if;
		return 0;
	end function;

	-- Contadores de eventos do Zihpm instanciados no banco de CSRs.
	constant HPM_COUNT : natural range 0 to 4 := effective_hpm_count;

	-- =========================================================================
	-- Sinais globais de avanço, stall e flush entre estágios
	-- =========================================================================
	-- Indica que a unidade multdiv está ocupada no estágio EX.
	signal muldiv_stall      : std_logic;
	-- Pulso de término de uma operação M fundida com a anterior (evento 9 do Zihpm).
	signal muldiv_fused      : std_logic;
	-- Indica que o barramento externo SDRAM está em espera no estágio MEM.
	signal sdram_wait        : std_logic;
	-- Indica que a unidade FENCE.I aguarda o flush da cache de dados no estágio EX.
	signal fencei_busy       : std_logic;
	-- Indica que os estágios EX e MEM estão livres de stalls de execução/memória.
	signal base_run          : std_logic;
	-- Stall global combinado para a unidade de detecção de hazards (HDU).
	signal pipe_stall        : std_logic;
	-- Habilitação de avanço para o registrador ID/EX e estágios anteriores a MEM.
	signal pipe_run          : std_logic;
	-- Vetor de eventos dos contadores do Zihpm, um bit por código de evento.
	signal hpm_events        : std_logic_vector(15 downto 0);
	-- Valor de mis_stall no ciclo anterior (para o pulso de início de um acesso desalinhado).
	signal mis_stall_q       : std_logic := '0';
	-- Ciclo de parada por dependência de load: a HDU parou o IF/ID sem que o pipeline estivesse parado por outro motivo.
	signal load_use_stall    : std_logic;

	-- Sinal de flush síncrono do registrador IF/ID.
	signal flush_if_id       : std_logic;
	-- Sinal de flush síncrono do registrador ID/EX.
	signal flush_id_ex       : std_logic;
	-- Sinal de flush síncrono do registrador EX/MEM.
	signal flush_ex_mem      : std_logic;
	-- Pulso de exceção sinalizada sem Zicsr, que mata a instrução em EX sem redirecionar o PC.
	signal trap_sig          : std_logic;
	-- A memória avança neste ciclo: sem parada de multdiv nem espera da SDRAM, mesmo com a etapa 1 de um acesso desalinhado.
	signal mem_run           : std_logic;
	-- O acesso em MEM cruza a palavra e é executado em duas etapas.
	signal mis_cross         : std_logic;
	-- Etapa 1 de um acesso desalinhado em andamento: o pipeline espera.
	signal mis_stall         : std_logic;
	-- Endereço da etapa corrente do acesso desalinhado.
	signal mis_addr          : word_t;
	-- Dado de escrita da etapa corrente do acesso desalinhado.
	signal mis_data          : word_t;
	-- Máscara de bytes da etapa corrente do acesso desalinhado.
	signal mis_mask          : byte_mask_t;
	-- Primeira palavra lida por um load desalinhado, retida para o estágio WB.
	signal mis_first_word    : word_t;
	-- Região FLASH do load em WB, decodificada na entrada do registrador MEM/WB.
	signal memwb_is_flash    : std_logic;
	-- Região SDRAM do load em WB, decodificada na entrada do registrador MEM/WB.
	signal memwb_is_sdram    : std_logic;
	-- Cruzamento de palavra do load em WB, decodificado na entrada do registrador MEM/WB.
	signal memwb_is_cross    : std_logic;
	-- Endereço que o estágio MEM de fato apresenta às memórias.
	signal mem_addr          : word_t;
	-- Dado de escrita que o estágio MEM de fato apresenta às memórias.
	signal mem_wdata         : word_t;
	-- Máscara de bytes que o estágio MEM de fato apresenta às memórias.
	signal mem_mask          : byte_mask_t;

	-- =========================================================================
	-- Sinais do Estágio IF -> Registrador IF/ID
	-- =========================================================================
	-- Endereço PC atual gerado no estágio IF.
	signal if_pc             : word_t;
	-- Endereço PC + 4 gerado no estágio IF.
	signal if_pc4            : word_t;
	-- Instrução de 32 bits buscada no estágio IF.
	signal if_instr          : word_t;
	-- Validade da instrução buscada no estágio IF.
	signal if_instr_valid    : std_logic;

	-- =========================================================================
	-- Sinais do Registrador IF/ID -> Estágio ID
	-- =========================================================================
	-- Bit de validade registrado em IF/ID.
	signal ifid_valid        : std_logic;
	-- Endereço PC registrado em IF/ID.
	signal ifid_pc           : word_t;
	-- Endereço PC + 4 registrado em IF/ID.
	signal ifid_pc4          : word_t;
	-- Instrução de 32 bits registrada em IF/ID.
	signal ifid_instr        : word_t;

	-- =========================================================================
	-- Sinais do Estágio ID -> Registrador ID/EX (e HDU)
	-- =========================================================================
	-- Habilitação de atualização do PC gerada pela HDU no estágio ID.
	signal id_pc_we          : std_logic;
	-- Habilitação de atualização do registrador IF/ID gerada pela HDU no estágio ID.
	signal ifid_write_en     : std_logic;
	-- Bit de validade de entrada do registrador ID/EX após filtragem de bolha.
	signal id_valid_out      : std_logic;
	-- Índice do registrador fonte rs1 decodificado no estágio ID.
	signal id_rs1_idx        : reg_t;
	-- Índice do registrador fonte rs2 decodificado no estágio ID.
	signal id_rs2_idx        : reg_t;
	-- Índice do registrador destino rd decodificado no estágio ID.
	signal id_rd_idx         : reg_t;
	-- Valor de 32 bits lido de rs1 no estágio ID.
	signal id_rs1_val        : word_t;
	-- Valor de 32 bits lido de rs2 no estágio ID.
	signal id_rs2_val        : word_t;
	-- Imediato estendido de 32 bits gerado no estágio ID.
	signal id_imm            : word_t;
	-- Seletor entre resultado de execução e PC + 4 gerado no estágio ID.
	signal id_sel_pc4_alu    : std_logic;
	-- Seletor de fonte de Write-Back gerado no estágio ID.
	signal id_wb_sel         : wb_sel_t;
	-- Habilitação de escrita no banco de registradores gerada no estágio ID.
	signal id_we_reg         : std_logic;
	-- Modo de extensão de leitura da memória de dados gerado no estágio ID.
	signal id_ext_ram_op     : ext_ram_op_t;
	-- Seletor entre rs2 e imediato gerado no estágio ID.
	signal id_sel_rs2_imm    : std_logic;
	-- Seletor entre PC e rs1 gerado no estágio ID.
	signal id_sel_pc_rs1     : std_logic;
	-- Código de operação da ULA gerado no estágio ID.
	signal id_alu_op         : alu_op_t;
	-- Seleção one-hot do resultado da ULA decodificada no estágio ID.
	signal id_alu_sel        : alu_sel_t;
	-- Casamentos do adiantamento de rs1 calculados no estágio ID.
	signal id_fwd_match_rs1  : fwd_match_t;
	-- Casamentos do adiantamento de rs2 calculados no estágio ID.
	signal id_fwd_match_rs2  : fwd_match_t;
	-- Indicador de instrução da extensão M gerado no estágio ID.
	signal id_is_muldiv      : std_logic;
	-- Indicador de instrução da extensão Zicsr gerado no estágio ID.
	signal id_is_csr         : std_logic;
	-- Indicador de instrução inexistente gerado no estágio ID.
	signal id_illegal        : std_logic;
	-- Habilitação de escrita na memória de dados gerada no estágio ID.
	signal id_we_ram         : std_logic;
	-- Habilitação de leitura na memória de dados gerada no estágio ID.
	signal id_re_ram         : std_logic;
	-- Habilitação geral da memória de dados gerada no estágio ID.
	signal id_en_ram         : std_logic;
	-- Campo opcode extraído no estágio ID.
	signal id_opcode         : opcode_t;
	-- Campo funct3 extraído no estágio ID.
	signal id_funct3         : funct3_t;

	-- =========================================================================
	-- Sinais do Registrador ID/EX -> Estágio EX
	-- =========================================================================
	-- Bit de validade registrado em ID/EX.
	signal ex_valid          : std_logic;
	-- Endereço PC registrado em ID/EX.
	signal ex_pc             : word_t;
	-- Endereço PC + 4 registrado em ID/EX.
	signal ex_pc4            : word_t;
	-- Índice do registrador fonte rs1 registrado em ID/EX.
	signal ex_rs1_idx        : reg_t;
	-- Índice do registrador destino rd registrado em ID/EX.
	signal ex_rd_idx         : reg_t;
	-- Valor de rs1 registrado em ID/EX.
	signal ex_rs1_val        : word_t;
	-- Valor de rs2 registrado em ID/EX.
	signal ex_rs2_val        : word_t;
	-- Imediato estendido registrado em ID/EX.
	signal ex_imm            : word_t;
	-- Seletor entre execução e PC + 4 registrado em ID/EX.
	signal ex_sel_pc4_alu    : std_logic;
	-- Seletor de fonte de Write-Back registrado em ID/EX.
	signal ex_wb_sel         : wb_sel_t;
	-- Habilitação de escrita em registrador registrada em ID/EX.
	signal ex_we_reg         : std_logic;
	-- Modo de extensão de leitura da memória registrado em ID/EX.
	signal ex_ext_ram_op     : ext_ram_op_t;
	-- Seletor rs2/imediato registrado em ID/EX.
	signal ex_sel_rs2_imm    : std_logic;
	-- Seletor PC/rs1 registrado em ID/EX.
	signal ex_sel_pc_rs1     : std_logic;
	-- Código de operação da ULA registrado em ID/EX.
	signal ex_alu_op         : alu_op_t;
	-- Seleção one-hot do resultado da ULA registrada em ID/EX.
	signal ex_alu_sel        : alu_sel_t;
	-- Casamentos do adiantamento de rs1 registrados em ID/EX.
	signal ex_fwd_match_rs1  : fwd_match_t;
	-- Casamentos do adiantamento de rs2 registrados em ID/EX.
	signal ex_fwd_match_rs2  : fwd_match_t;
	-- Indicador de instrução da extensão M registrado em ID/EX.
	signal ex_is_muldiv      : std_logic;
	-- Indicador de instrução da extensão Zicsr registrado em ID/EX.
	signal ex_is_csr         : std_logic;
	-- Indicador de instrução inexistente registrado em ID/EX.
	signal ex_illegal        : std_logic;
	-- Habilitação de escrita na memória registrada em ID/EX.
	signal ex_we_ram         : std_logic;
	-- Habilitação de leitura na memória registrada em ID/EX.
	signal ex_re_ram         : std_logic;
	-- Habilitação geral da memória registrada em ID/EX.
	signal ex_en_ram         : std_logic;
	-- Campo opcode registrado em ID/EX.
	signal ex_opcode         : opcode_t;
	-- Campo funct3 registrado em ID/EX.
	signal ex_funct3         : funct3_t;

	-- =========================================================================
	-- Sinais do Estágio EX -> Registrador EX/MEM e Realimentação de Controle para IF
	-- =========================================================================
	-- Resultado final de 32 bits produzido no estágio EX.
	signal ex_final_result   : word_t;
	-- Dado alinhado para escrita em memória produzido no estágio EX.
	signal ex_store_data     : word_t;
	-- Máscara de bytes para escrita em memória produzida no estágio EX.
	signal ex_store_byteena  : byte_mask_t;
	-- Indica desvio condicional ou JAL tomado no estágio EX.
	signal ex_branch_taken   : std_logic;
	-- Indica salto indireto JALR tomado no estágio EX.
	signal ex_jalr_taken     : std_logic;
	-- Endereço alvo de branch condicional ou JAL calculado no estágio EX.
	signal ex_branch_target  : word_t;
	-- Endereço alvo de JALR calculado no estágio EX.
	signal ex_jalr_target    : word_t;
	-- Endereço de redirecionamento prioritário (mepc, PC + 4 ou mtvec) do estágio EX.
	signal ex_redirect_pc    : word_t;
	-- Pulso de tomada de exceção síncrona gerado no estágio EX.
	signal trap_take         : std_logic;
	-- Exceção de endereço do acesso à memória no estágio MEM (instrução mais antiga que a de EX).
	signal mem_trap_take     : std_logic;
	-- Causa (mcause) da exceção de MEM.
	signal mem_trap_cause    : word_t;
	-- Valor de mtval da exceção de MEM.
	signal mem_trap_tval     : word_t;
	-- Validade da instrução em EX descontada a exceção de MEM, que a descarta.
	signal ex_valid_live     : std_logic;
	-- Exceção síncrona em EX ou em MEM: redireciona o PC para o vetor de traps.
	signal any_trap_take     : std_logic;
	-- Instrução em MEM válida e sem exceção de endereço, liberada para a unidade de acesso desalinhado.
	signal mis_valid         : std_logic;
	-- PC da instrução em MEM trazido de EX/MEM.
	signal exmem_pc          : word_t;
	-- Campo funct3 da instrução em MEM trazido de EX/MEM.
	signal exmem_funct3      : funct3_t;
	-- Pulso de retirada de uma instrução em EX: válida, com o pipeline andando e sem exceção.
	signal retire_pulse      : std_logic;
	-- Pulso de retorno de exceção (MRET) gerado no estágio EX.
	signal mret_take         : std_logic;
	-- Pulso de conclusão de FENCE.I gerado no estágio EX.
	signal fencei_take       : std_logic;
	-- Conclusão de FENCE.I antes do descarte pela exceção de MEM, que invalida a cache de instruções.
	signal fencei_inval      : std_logic;

	-- =========================================================================
	-- Sinais do Registrador EX/MEM -> Estágio MEM e Registrador MEM/WB
	-- =========================================================================
	-- Bit de validade registrado em EX/MEM.
	signal exmem_valid       : std_logic;
	-- Resultado do estágio EX (endereço de memória ou dado) registrado em EX/MEM.
	signal exmem_alu_out     : word_t;
	-- Dado alinhado para escrita em memória registrado em EX/MEM.
	signal exmem_store_data  : word_t;
	-- Máscara de habilitação de bytes registrada em EX/MEM.
	signal exmem_byteena     : byte_mask_t;
	-- Índice do registrador destino rd registrado em EX/MEM.
	signal exmem_rd_idx      : reg_t;
	-- Habilitação de escrita em registrador registrada em EX/MEM.
	signal exmem_we_reg      : std_logic;
	-- A instrução em EX/MEM é válida e escreve em registrador.
	signal exmem_ok          : std_logic;
	-- Habilitação de escrita na memória registrada em EX/MEM.
	signal exmem_we_ram      : std_logic;
	-- Habilitação de leitura na memória registrada em EX/MEM.
	signal exmem_re_ram      : std_logic;
	-- Habilitação geral da memória registrada em EX/MEM.
	signal exmem_en_ram      : std_logic;
	-- Modo de extensão de leitura da memória registrado em EX/MEM.
	signal exmem_ext_ram_op  : ext_ram_op_t;
	-- Seletor de fonte de Write-Back registrado em EX/MEM.
	signal exmem_wb_sel      : wb_sel_t;

	-- =========================================================================
	-- Sinais do Registrador MEM/WB -> Estágio WB
	-- =========================================================================
	-- Bit de validade registrado em MEM/WB.
	signal memwb_valid       : std_logic;
	-- Resultado da ULA/execução registrado em MEM/WB.
	signal memwb_alu_out     : word_t;
	-- Índice do registrador destino rd registrado em MEM/WB.
	signal memwb_rd_idx      : reg_t;
	-- Habilitação de escrita em registrador registrada em MEM/WB.
	signal memwb_we_reg      : std_logic;
	-- A instrução em MEM/WB é válida e escreve em registrador.
	signal memwb_ok          : std_logic;
	-- Modo de extensão de leitura da memória registrado em MEM/WB.
	signal memwb_ext_ram_op  : ext_ram_op_t;
	-- Seletor de fonte de Write-Back registrado em MEM/WB.
	signal memwb_wb_sel      : wb_sel_t;

	-- =========================================================================
	-- Sinais do Estágio WB -> Realimentação para ID (RegFile) e EX (Forwarding)
	-- =========================================================================
	-- Habilitação final de escrita no banco de registradores.
	signal wb_we             : std_logic;
	-- Índice final do registrador destino rd para escrita no RegFile.
	signal wb_rd             : reg_t;
	-- Dado de 32 bits selecionado no estágio WB, como a memória o entrega neste ciclo.
	signal wb_data_raw       : word_t;
	-- Próximo valor de wb_repeat: o ciclo atual é um stall de EX/MEM (base_run = '0').
	signal wb_repeat_nxt     : std_logic;
	-- Indica que o ciclo anterior foi um stall de EX/MEM (base_run = '0'): WB repete a instrução.
	signal wb_repeat         : std_logic;
	-- Dado entregue por WB no ciclo anterior (o que a instrução em WB escreveu primeiro).
	signal wb_data_prev      : word_t;
	-- Dado final de 32 bits do estágio WB: o primeiro ciclo da instrução, repetido enquanto ela é segurada.
	signal wb_data           : word_t;
	-- Escrita no banco de registradores da instrução que saiu de WB no ciclo anterior (registrador WB2).
	signal wb2_we            : std_logic;
	-- Registrador destino rd da instrução em WB2.
	signal wb2_rd            : reg_t;
	-- Dado final de write-back da instrução em WB2.
	signal wb2_data          : word_t;

begin

	-- Coordenação global de stalls e flushes entre os estágios.
	mem_run       <= not (muldiv_stall or sdram_wait);
	base_run      <= mem_run and (not mis_stall);
	pipe_stall    <= muldiv_stall or sdram_wait or fencei_busy or mis_stall;
	pipe_run      <= base_run and (not fencei_busy);
	o_mem_advance <= mem_run;
	-- Com CSRs, a exceção de endereço do load ou store é tomada em MEM (mem_trap_take): é de uma instrução mais
	-- antiga que a de EX, então redireciona o pipeline e descarta a instrução de EX. Sem CSRs, o endereço é
	-- conferido em EX junto das demais causas, que só são sinalizadas, e mem_trap_take fica em zero.
	ex_valid_live <= ex_valid and (not mem_trap_take);
	any_trap_take <= trap_take or mem_trap_take;
	mis_valid     <= exmem_valid and (not mem_trap_take);

	o_trap        <= trap_sig;
	retire_pulse  <= ex_valid_live and pipe_run and (not trap_take) and (not trap_sig);

	-- Eventos do Zihpm (códigos de csr_event_consts): 1 parada de multdiv, 2 espera externa, 3 desvio tomado,
	-- 4 início de acesso desalinhado, 5 a 7 das caches e da FLASH, 8 parada por dependência de load.
	load_use_stall <= (not id_pc_we) and (not pipe_stall);
	process (i_clk)
	begin
		if rising_edge(i_clk) then
			mis_stall_q <= mis_stall;
		end if;
	end process;
	hpm_events <= (1 => muldiv_stall,
	               2 => sdram_wait,
	               3 => (ex_branch_taken or ex_jalr_taken) and pipe_run,
	               4 => mis_stall and (not mis_stall_q),
	               5 => i_hpm_ext_events(0),
	               6 => i_hpm_ext_events(1),
	               7 => i_hpm_ext_events(2),
	               8 => load_use_stall,
	               9 => muldiv_fused,
	               others => '0');
	o_retire      <= retire_pulse;

	-- Os contadores são CSRs: sem Zicsr não há onde lê-los.
	assert has_zicsr or (not (has_zicntr or has_zihpm or hpm_counters > 0))
		report "has_zicntr = true exige has_zicsr"
		severity failure;


	flush_if_id   <= ((ex_branch_taken or ex_jalr_taken) and pipe_run) or trap_take or mem_trap_take or mret_take or fencei_take;
	flush_id_ex   <= ((ex_branch_taken or ex_jalr_taken) and pipe_run) or trap_take or mem_trap_take or mret_take or fencei_take;
	flush_ex_mem  <= trap_take or trap_sig or mem_trap_take or (fencei_busy and base_run);

	-- =========================================================================
	-- 1. Estágio IF (Instruction Fetch) + Registrador IF/ID
	-- =========================================================================
	u_stage_if : entity work.stage_if
		generic map (
			ext_flash => ext_flash
		)
		port map (
			i_clk             => i_clk,
			i_rst             => i_rst,
			i_hdu_pc_we       => id_pc_we,
			i_pipe_run        => pipe_run,
			i_ex_branch_taken => ex_branch_taken,
			i_ex_jalr_taken   => ex_jalr_taken,
			i_trap_take       => any_trap_take,
			i_mret_take       => mret_take,
			i_fencei_take     => fencei_take,
			i_ic_inval        => fencei_inval,
			i_branch_target   => ex_branch_target,
			i_jalr_target     => ex_jalr_target,
			i_redirect_pc     => ex_redirect_pc,
			i_boot_rom_data   => i_boot_rom_data,
			i_flash_data      => i_flash_data,
			i_ic_data         => i_ic_data,
			i_ic_ready        => i_ic_ready,
			o_pc              => if_pc,
			o_pc4             => if_pc4,
			o_instr           => if_instr,
			o_instr_valid     => if_instr_valid,
			o_if_addr         => o_if_addr,
			o_if_rden         => o_if_rden,
			o_ic_sel          => o_ic_sel,
			o_ic_inval        => o_ic_inval
		);

	u_reg_if_id : entity work.reg_if_id
		port map (
			i_clk   => i_clk,
			i_rst   => i_rst,
			i_en    => ifid_write_en,
			i_flush => flush_if_id,
			i_valid => if_instr_valid,
			i_pc    => if_pc,
			i_pc4   => if_pc4,
			i_inst  => if_instr,
			o_valid => ifid_valid,
			o_pc    => ifid_pc,
			o_pc4   => ifid_pc4,
			o_inst  => ifid_instr
		);

	-- =========================================================================
	-- 2. Estágio ID (Instruction Decode) + Registrador ID/EX
	-- =========================================================================
	u_stage_id : entity work.stage_id
		generic map (
			has_m        => has_m,
			has_zmmul    => has_zmmul,
			has_zicsr    => has_zicsr,
			has_zifencei => has_zifencei
		)
		port map (
			i_clk         => i_clk,
			i_rst         => i_rst,
			i_ifid_valid  => ifid_valid,
			i_instr       => ifid_instr,
			i_wb_we       => wb2_we,
			i_wb_rd       => wb2_rd,
			i_wb_data     => wb2_data,
			i_mem_rd      => exmem_rd_idx,
			i_mem_we_reg  => exmem_we_reg,
			i_memwb_rd    => memwb_rd_idx,
			i_memwb_we_reg => memwb_we_reg,
			i_mem_re_ram  => exmem_re_ram,
			i_ex_rd       => ex_rd_idx,
			i_ex_we_reg   => ex_we_reg,
			i_ex_re_ram   => ex_re_ram,
			i_pipe_stall  => pipe_stall,
			o_pc_we       => id_pc_we,
			o_ifid_we     => ifid_write_en,
			o_idex_valid  => id_valid_out,
			o_rs1_idx     => id_rs1_idx,
			o_rs2_idx     => id_rs2_idx,
			o_rd_idx      => id_rd_idx,
			o_rs1_val     => id_rs1_val,
			o_rs2_val     => id_rs2_val,
			o_imm         => id_imm,
			o_sel_pc4_alu => id_sel_pc4_alu,
			o_wb_sel      => id_wb_sel,
			o_we_reg      => id_we_reg,
			o_ext_ram_op  => id_ext_ram_op,
			o_sel_rs2_imm => id_sel_rs2_imm,
			o_sel_pc_rs1  => id_sel_pc_rs1,
			o_alu_op      => id_alu_op,
			o_alu_sel     => id_alu_sel,
			o_fwd_match_rs1 => id_fwd_match_rs1,
			o_fwd_match_rs2 => id_fwd_match_rs2,
			o_is_muldiv   => id_is_muldiv,
			o_is_csr      => id_is_csr,
			o_illegal     => id_illegal,
			o_we_ram      => id_we_ram,
			o_re_ram      => id_re_ram,
			o_en_ram      => id_en_ram,
			o_opcode      => id_opcode,
			o_funct3      => id_funct3
		);

	u_reg_id_ex : entity work.reg_id_ex
		port map (
			i_clk         => i_clk,
			i_rst         => i_rst,
			i_en          => pipe_run,
			i_flush       => flush_id_ex,
			i_valid       => id_valid_out,
			i_pc          => ifid_pc,
			i_pc4         => ifid_pc4,
			i_rs1         => id_rs1_idx,
			i_rd          => id_rd_idx,
			i_rs1_val     => id_rs1_val,
			i_rs2_val     => id_rs2_val,
			i_imm         => id_imm,
			i_sel_pc4_alu => id_sel_pc4_alu,
			i_wb_sel      => id_wb_sel,
			i_we_reg      => id_we_reg,
			i_ext_ram_op  => id_ext_ram_op,
			i_sel_rs2_imm => id_sel_rs2_imm,
			i_sel_pc_rs1  => id_sel_pc_rs1,
			i_alu_op      => id_alu_op,
			i_alu_sel     => id_alu_sel,
			i_fwd_match_rs1 => id_fwd_match_rs1,
			i_fwd_match_rs2 => id_fwd_match_rs2,
			i_is_muldiv   => id_is_muldiv,
			i_is_csr      => id_is_csr,
			i_illegal     => id_illegal,
			i_we_ram      => id_we_ram,
			i_re_ram      => id_re_ram,
			i_en_ram      => id_en_ram,
			i_opcode      => id_opcode,
			i_funct3      => id_funct3,
			o_valid       => ex_valid,
			o_pc          => ex_pc,
			o_pc4         => ex_pc4,
			o_rs1         => ex_rs1_idx,
			o_rd          => ex_rd_idx,
			o_rs1_val     => ex_rs1_val,
			o_rs2_val     => ex_rs2_val,
			o_imm         => ex_imm,
			o_sel_pc4_alu => ex_sel_pc4_alu,
			o_wb_sel      => ex_wb_sel,
			o_we_reg      => ex_we_reg,
			o_ext_ram_op  => ex_ext_ram_op,
			o_sel_rs2_imm => ex_sel_rs2_imm,
			o_sel_pc_rs1  => ex_sel_pc_rs1,
			o_alu_op      => ex_alu_op,
			o_alu_sel     => ex_alu_sel,
			o_fwd_match_rs1 => ex_fwd_match_rs1,
			o_fwd_match_rs2 => ex_fwd_match_rs2,
			o_is_muldiv   => ex_is_muldiv,
			o_is_csr      => ex_is_csr,
			o_illegal     => ex_illegal,
			o_we_ram      => ex_we_ram,
			o_re_ram      => ex_re_ram,
			o_en_ram      => ex_en_ram,
			o_opcode      => ex_opcode,
			o_funct3      => ex_funct3
		);

	-- =========================================================================
	-- 3. Estágio EX (Execute) + Registrador EX/MEM
	-- =========================================================================
	u_stage_ex : entity work.stage_ex
		generic map (
			has_m        => has_m,
			has_zmmul    => has_zmmul,
			has_zicsr    => has_zicsr,
			has_zicntr   => has_zicntr,
			tick_cycles  => tick_cycles,
			has_zifencei => has_zifencei,
			has_zicclsm  => has_zicclsm,
			has_dcache   => has_dcache,
			hpm_counters => HPM_COUNT
		)
		port map (
			i_hpm_events      => hpm_events,
			i_clk             => i_clk,
			i_rst             => i_rst,
			i_base_run        => base_run,
			i_pipe_run        => pipe_run,
			i_valid           => ex_valid_live,
			i_valid_raw       => ex_valid,
			i_mem_trap_take   => mem_trap_take,
			i_mem_trap_cause  => mem_trap_cause,
			i_mem_trap_pc     => exmem_pc,
			i_mem_trap_tval   => mem_trap_tval,
			i_retire          => retire_pulse,
			i_pc              => ex_pc,
			i_pc4             => ex_pc4,
			i_rs1_idx         => ex_rs1_idx,
			i_rd_idx          => ex_rd_idx,
			i_rs1_val         => ex_rs1_val,
			i_rs2_val         => ex_rs2_val,
			i_imm             => ex_imm,
			i_sel_pc4_alu     => ex_sel_pc4_alu,
			i_sel_rs2_imm     => ex_sel_rs2_imm,
			i_sel_pc_rs1      => ex_sel_pc_rs1,
			i_alu_op          => ex_alu_op,
			i_alu_sel         => ex_alu_sel,
			i_is_muldiv       => ex_is_muldiv,
			i_is_csr          => ex_is_csr,
			i_illegal         => ex_illegal,
			i_opcode          => ex_opcode,
			i_funct3          => ex_funct3,
			i_fwd_match_rs1   => ex_fwd_match_rs1,
			i_fwd_match_rs2   => ex_fwd_match_rs2,
			i_exmem_ok        => exmem_ok,
			i_memwb_ok        => memwb_ok,
			i_wb2_ok          => wb2_we,
			i_exmem_alu_out   => exmem_alu_out,
			i_memwb_alu_out   => memwb_alu_out,
			i_wb2_data        => wb2_data,
			i_dc_done         => i_dc_done,
			o_final_result    => ex_final_result,
			o_store_data      => ex_store_data,
			o_store_byte_mask => ex_store_byteena,
			o_branch_taken    => ex_branch_taken,
			o_jalr_taken      => ex_jalr_taken,
			o_branch_target   => ex_branch_target,
			o_jalr_target     => ex_jalr_target,
			o_redirect_pc     => ex_redirect_pc,
			o_trap_take       => trap_take,
			o_trap_sig        => trap_sig,
			o_trap_sig_cause  => o_trap_cause,
			o_trap_sig_pc     => o_trap_pc,
			o_mret_take       => mret_take,
			o_fencei_take     => fencei_take,
			o_fencei_inval    => fencei_inval,
			o_fencei_busy     => fencei_busy,
			o_dc_flush        => o_dc_flush,
			o_muldiv_stall    => muldiv_stall,
			o_muldiv_fused    => muldiv_fused
		);

	u_reg_ex_mem : entity work.reg_ex_mem
		port map (
			i_clk        => i_clk,
			i_rst        => i_rst,
			i_en         => base_run,
			i_flush      => flush_ex_mem,
			i_valid      => ex_valid_live,
			i_pc         => ex_pc,
			i_funct3     => ex_funct3,
			i_alu_out    => ex_final_result,
			i_store_data => ex_store_data,
			i_byte_mask  => ex_store_byteena,
			i_rd         => ex_rd_idx,
			i_we_reg     => ex_we_reg,
			i_we_ram     => ex_we_ram,
			i_re_ram     => ex_re_ram,
			i_en_ram     => ex_en_ram,
			i_ext_ram_op => ex_ext_ram_op,
			i_wb_sel     => ex_wb_sel,
			o_valid      => exmem_valid,
			o_alu_out    => exmem_alu_out,
			o_store_data => exmem_store_data,
			o_byte_mask  => exmem_byteena,
			o_rd         => exmem_rd_idx,
			o_we_reg     => exmem_we_reg,
			o_we_ok      => exmem_ok,
			o_we_ram     => exmem_we_ram,
			o_re_ram     => exmem_re_ram,
			o_en_ram     => exmem_en_ram,
			o_ext_ram_op => exmem_ext_ram_op,
			o_wb_sel     => exmem_wb_sel,
			o_pc         => exmem_pc,
			o_funct3     => exmem_funct3
		);

	-- =========================================================================
	-- 4. Estágio MEM (Memory Access) + Registrador MEM/WB
	-- =========================================================================
	u_misaligned_unit : entity work.misaligned_unit
		generic map (
			has_zicclsm => has_zicclsm,
			ext_flash   => ext_flash
		)
		port map (
			i_clk         => i_clk,
			i_rst         => i_rst,
			i_valid       => mis_valid,
			i_en          => exmem_en_ram,
			i_re          => exmem_re_ram,
			i_we          => exmem_we_ram,
			i_ext_op      => exmem_ext_ram_op,
			i_byte_mask   => exmem_byteena,
			i_addr        => exmem_alu_out,
			i_store_data  => exmem_store_data,
			i_ready       => i_sdram_ready,
			i_advance     => mem_run,
			i_base_run    => base_run,
			i_ram_rdata   => i_ram_rdata,
			i_sdram_rdata => i_sdram_rdata,
			o_cross       => mis_cross,
			o_stall       => mis_stall,
			o_addr        => mis_addr,
			o_data        => mis_data,
			o_mask        => mis_mask,
			o_first_word  => mis_first_word
		);

	mem_addr  <= mis_addr when mis_cross = '1' else exmem_alu_out;
	mem_wdata <= mis_data when mis_cross = '1' else exmem_store_data;
	mem_mask  <= mis_mask when mis_cross = '1' else exmem_byteena;

	u_stage_mem : entity work.stage_mem
		generic map (
			has_zicclsm => has_zicclsm,
			check_ea    => has_zicsr,
			ext_flash   => ext_flash
		)
		port map (
			i_valid         => exmem_valid,
			i_alu_out       => mem_addr,
			i_ea            => exmem_alu_out,
			i_funct3        => exmem_funct3,
			i_store_data    => mem_wdata,
			i_byte_mask     => mem_mask,
			i_we_ram        => exmem_we_ram,
			i_re_ram        => exmem_re_ram,
			i_en_ram        => exmem_en_ram,
			i_sdram_ready   => i_sdram_ready,
			o_flash_addr2   => o_flash_addr2,
			o_flash_rden2   => o_flash_rden2,
			o_ram_addr      => o_ram_addr,
			o_ram_wdata     => o_ram_wdata,
			o_ram_en        => o_ram_en,
			o_ram_wren      => o_ram_wren,
			o_ram_rden      => o_ram_rden,
			o_ram_byteena   => o_ram_byteena,
			o_sdram_addr    => o_sdram_addr,
			o_sdram_wdata   => o_sdram_wdata,
			o_sdram_byteena => o_sdram_byteena,
			o_sdram_rden    => o_sdram_rden,
			o_sdram_wren    => o_sdram_wren,
			o_sdram_wait    => sdram_wait,
			o_trap_take     => mem_trap_take,
			o_trap_cause    => mem_trap_cause,
			o_trap_tval     => mem_trap_tval
		);

	u_reg_mem_wb : entity work.reg_mem_wb
		generic map (
			ext_flash => ext_flash
		)
		port map (
			i_clk        => i_clk,
			i_rst        => i_rst,
			i_en         => base_run,
			i_flush      => mem_trap_take,
			i_valid      => exmem_valid,
			i_alu_out    => exmem_alu_out,
			i_rd         => exmem_rd_idx,
			i_we_reg     => exmem_we_reg,
			i_ext_ram_op => exmem_ext_ram_op,
			i_wb_sel     => exmem_wb_sel,
			o_valid      => memwb_valid,
			o_alu_out    => memwb_alu_out,
			o_rd         => memwb_rd_idx,
			o_we_reg     => memwb_we_reg,
			o_we_ok      => memwb_ok,
			o_ext_ram_op => memwb_ext_ram_op,
			o_wb_sel     => memwb_wb_sel,
			o_is_flash   => memwb_is_flash,
			o_is_sdram   => memwb_is_sdram,
			o_is_cross   => memwb_is_cross
		);

	-- =========================================================================
	-- 5. Estágio WB (Write-Back)
	-- =========================================================================
	u_stage_wb : entity work.stage_wb
		port map (
			i_valid       => memwb_valid,
			i_alu_out     => memwb_alu_out,
			i_rd_idx      => memwb_rd_idx,
			i_we_reg      => memwb_we_reg,
			i_ext_ram_op  => memwb_ext_ram_op,
			i_wb_sel      => memwb_wb_sel,
			i_is_flash    => memwb_is_flash,
			i_is_sdram    => memwb_is_sdram,
			i_is_cross    => memwb_is_cross,
			i_flash_data2 => i_flash_data2,
			i_ram_rdata   => i_ram_rdata,
			i_first_word  => mis_first_word,
			i_sdram_rdata => i_sdram_rdata,
			o_wb_we       => wb_we,
			o_wb_rd       => wb_rd,
			o_wb_data     => wb_data_raw
		);

	-- A instrução em WB é segurada enquanto base_run = '0' e escreve o banco de registradores e o
	-- forwarding a cada ciclo desse stall. A memória síncrona, porém, passa a responder ao endereço
	-- da instrução parada em MEM, então o dado de um load em WB só vale no primeiro ciclo. Os ciclos
	-- seguintes repetem o dado do ciclo anterior.
	wb_repeat_nxt <= not base_run;

	u_wb_repeat_ff : entity work.flip_flop
		port map (
			i_d      => wb_repeat_nxt,
			o_d      => wb_repeat,
			i_enable => '1',
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	u_wb_data_prev_reg : entity work.generic_register
		generic map (
			data_width => word_t'length
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => '1',
			i_d      => wb_data,
			o_d      => wb_data_prev
		);

	-- O banco de registradores é escrito e o adiantamento é feito a partir do registrador WB2: o dado alinhado
	-- de um load fica pronto em WB e só sai dali para o resto do pipeline registrado, o que tira o alinhamento
	-- do caminho de adiantamento. Um load seguido de uma instrução dependente espera por isso um ciclo a mais.
	-- WB2 avança junto de MEM/WB (base_run), para que uma parada não troque a instrução que o adiantamento vê.
	u_wb2_we_ff : entity work.flip_flop
		port map (
			i_d      => wb_we,
			o_d      => wb2_we,
			i_enable => base_run,
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	u_wb2_rd_reg : entity work.generic_register
		generic map (
			data_width => reg_t'length
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => base_run,
			i_d      => wb_rd,
			o_d      => wb2_rd
		);

	u_wb2_data_reg : entity work.generic_register
		generic map (
			data_width => word_t'length
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => base_run,
			i_d      => wb_data,
			o_d      => wb2_data
		);

	u_mux_wb_data : entity work.mux_2x1
		generic map (
			data_width => word_t'length
		)
		port map (
			i_d0  => wb_data_raw,
			i_d1  => wb_data_prev,
			i_sel => wb_repeat,
			o_d   => wb_data
		);

end architecture rtl;
