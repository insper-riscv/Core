-- =============================================================================
-- Estágio MEM (Memory Access) do Pipeline RV32
--
-- Decodifica o endereço efetivo calculado no estágio EX (i_alu_out) usando as
-- constantes centralizadas em mem_map_consts e roteia os sinais de leitura,
-- escrita e máscara de bytes para os três subsistemas de memória de dados.
-- Antes de rotear, confere o endereço efetivo original (i_ea) do load ou store:
-- um acesso desalinhado que o hardware não executa gera a exceção de endereço
-- (o_trap_take) já neste estágio, e nenhum acesso à memória é emitido:
--   1. Segunda porta da memória FLASH (< RAM_BASE_BYTES): leitura de constantes
--      e inicialização da seção .data no boot.
--   2. Memória RAM interna (RAM_BASE_BYTES .. SDRAM_BASE_BYTES - 1): leitura e
--      escrita síncrona de 1 ciclo de latência.
--   3. Barramento externo de SDRAM e periféricos (>= SDRAM_BASE_BYTES): leitura
--      e escrita com handshake de latência variável (i_sdram_ready / o_sdram_wait).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.mem_map_consts.all;
use work.opcode_consts.all;

entity stage_mem is
	generic (
		-- Executa em hardware o acesso desalinhado à memória principal (extensão Zicclsm); '0' faz todo desalinhado gerar trap.
		has_zicclsm     : boolean := true;
		-- Confere o endereço efetivo do load ou store (exceção em MEM); '0' deixa essa conferência para o estágio EX.
		check_ea        : boolean := true;
		-- Expoente do tamanho da BOOT_MEMORY: ela ocupa os endereços [0, 2**boot_memory_bits).
		boot_memory_bits   : natural := 12;
		-- Fim exclusivo, em KiB, da ROM, que começa logo depois da BOOT_MEMORY.
		rom_end_kib     : natural := 32;
		-- A ROM é externa quando é alcançada pela porta do núcleo (o_sdram_* ou a porta de instruções): a instrução sai pela porta de instruções e o dado pela porta externa, e a memória por trás pode ser externa ao chip ou uma memória interna atrás de cache.
		rom_external    : boolean := false;
		-- Base, em KiB, da RAM.
		ram_base_kib    : natural := 32;
		-- Fim exclusivo, em KiB, da RAM.
		ram_end_kib     : natural := 1048576;
		-- A RAM é externa quando é alcançada pela porta do núcleo (o_sdram_*): o dado sai pela porta externa, e a memória por trás pode ser externa ao chip ou uma memória interna atrás de cache.
		ram_external    : boolean := false;
		-- Base, em KiB, da janela externa: todo endereço a partir dela sai pela porta externa.
		ext_base_kib    : natural := 1048576;
		-- Base, em KiB, da janela de periféricos: o fim da memória principal que o desalinhamento em hardware atende.
		periph_base_kib : natural := 2097152;
		-- A classificação do endereço efetivo (FLASH, SDRAM, memória principal, mesma região) vem registrada do EX/MEM pelas portas i_flag_*, em vez de ser decodificada do endereço neste estágio.
		flags_registered : boolean := false
	);
	port (
		-- Bit de validade da instrução no estágio MEM.
		i_valid         : in  std_logic;
		-- Endereço apresentado às memórias neste ciclo (o efetivo, ou o da segunda palavra de um acesso que cruza).
		i_alu_out       : in  word_t;
		-- Endereço efetivo original do load ou store, vindo do registrador EX/MEM.
		i_ea            : in  word_t;
		-- O endereço efetivo cai na FLASH de dados (com flags_registered).
		i_flag_flash    : in  std_logic := '0';
		-- O endereço efetivo cai na janela externa, a SDRAM (com flags_registered).
		i_flag_sdram    : in  std_logic := '0';
		-- O endereço efetivo está na memória principal (com flags_registered).
		i_flag_main     : in  std_logic := '0';
		-- As duas palavras de um acesso que cruza ficam na mesma região (com flags_registered).
		i_flag_same     : in  std_logic := '0';
		-- Campo funct3 do load ou store, vindo do registrador EX/MEM.
		i_funct3        : in  funct3_t;
		-- Dado alinhado para escrita em memória vindo do registrador EX/MEM.
		i_store_data    : in  word_t;
		-- Máscara de habilitação de bytes vinda do registrador EX/MEM.
		i_byte_mask     : in  byte_mask_t;
		-- Habilitação de escrita na memória vinda do registrador EX/MEM.
		i_we_ram        : in  std_logic;
		-- Habilitação de leitura na memória vinda do registrador EX/MEM.
		i_re_ram        : in  std_logic;
		-- Habilitação geral de acesso à memória vinda do registrador EX/MEM.
		i_en_ram        : in  std_logic;
		-- Sinaliza que o escravo externo SDRAM concluiu a transação atual.
		i_sdram_ready   : in  std_logic;
		-- Endereço de leitura enviado à segunda porta da memória FLASH.
		o_flash_addr2   : out word_t;
		-- Habilitação de leitura enviada à segunda porta da memória FLASH.
		o_flash_rden2   : out std_logic;
		-- Endereço de acesso enviado à memória RAM interna.
		o_ram_addr      : out word_t;
		-- Dado de escrita enviado à memória RAM interna.
		o_ram_wdata     : out word_t;
		-- Habilitação geral enviada à memória RAM interna.
		o_ram_en        : out std_logic;
		-- Habilitação de escrita enviada à memória RAM interna.
		o_ram_wren      : out std_logic;
		-- Habilitação de leitura enviada à memória RAM interna.
		o_ram_rden      : out std_logic;
		-- Máscara de bytes enviada à memória RAM interna.
		o_ram_byteena   : out byte_mask_t;
		-- Endereço de acesso enviado ao barramento externo SDRAM/periféricos.
		o_sdram_addr    : out word_t;
		-- Dado de escrita enviado ao barramento externo SDRAM/periféricos.
		o_sdram_wdata   : out word_t;
		-- Máscara de bytes enviada ao barramento externo SDRAM/periféricos.
		o_sdram_byteena : out byte_mask_t;
		-- Habilitação de leitura enviada ao barramento externo SDRAM/periféricos.
		o_sdram_rden    : out std_logic;
		-- Habilitação de escrita enviada ao barramento externo SDRAM/periféricos.
		o_sdram_wren    : out std_logic;
		-- Indica que o estágio MEM aguarda conclusão de acesso no barramento SDRAM.
		o_sdram_wait    : out std_logic;
		-- Exceção de endereço desalinhado do load ou store em MEM ('1' = tomar o trap neste ciclo).
		o_trap_take     : out std_logic;
		-- Código mcause da exceção (4 = load, 6 = store).
		o_trap_cause    : out word_t;
		-- Valor de mtval da exceção (o endereço efetivo).
		o_trap_tval     : out word_t
	);
end entity stage_mem;

architecture rtl of stage_mem is

	-- Indica que o endereço acessado pertence à memória FLASH (< RAM_BASE_BYTES).
	signal is_flash_data   : std_logic;
	-- Indica que o endereço acessado pertence à janela externa de SDRAM (>= SDRAM_BASE_BYTES).
	signal is_sdram        : std_logic;
	-- Indica que o endereço acessado pertence à memória RAM interna.
	signal is_ram_internal : std_logic;
	-- Indica transação válida endereçada ao barramento externo de SDRAM.
	signal sdram_access    : std_logic;
	-- Opcode do acesso em MEM (LOAD, STORE ou zero), reconstruído dos sinais de leitura e escrita.
	signal mem_opcode      : opcode_t;
	-- Exceção de endereço do acesso em MEM, antes de qualquer acesso à memória.
	signal trap_take_int   : std_logic;
	-- Validade do acesso em MEM descontada a exceção: só o acesso que não gera trap chega às memórias.
	signal access_valid    : std_logic;

begin

	mem_opcode <= OPCODE_LOAD  when i_re_ram = '1' else
	              OPCODE_STORE when i_we_ram = '1' else
	              (others => '0');

	u_ea_trap : entity work.trap_unit
		generic map (
			has_zicclsm     => has_zicclsm,
			check_ea        => check_ea,
			boot_memory_bits   => boot_memory_bits,
			rom_end_kib     => rom_end_kib,
			rom_external    => rom_external,
			ram_base_kib    => ram_base_kib,
			ram_end_kib     => ram_end_kib,
			ram_external    => ram_external,
			ext_base_kib    => ext_base_kib,
			periph_base_kib => periph_base_kib,
			ea_flags_external => flags_registered
		)
		port map (
			i_ea_main        => i_flag_main,
			i_ea_same_region => i_flag_same,
			i_ex_valid    => i_valid,
			i_run         => '1',
			i_opcode      => mem_opcode,
			i_funct3      => i_funct3,
			i_rd_idx      => REG_ZERO,
			i_rs1_idx     => REG_ZERO,
			i_imm12       => (others => '0'),
			i_ea          => i_ea,
			i_cf_taken    => '0',
			i_cf_target   => (others => '0'),
			i_csr_illegal => '0',
			i_illegal     => '0',
			o_take        => trap_take_int,
			o_mret_take   => open,
			o_cause       => o_trap_cause,
			o_tval        => o_trap_tval
		);

	o_trap_take  <= trap_take_int;
	access_valid <= i_valid and (not trap_take_int);

	-- A região sai da comparação do endereço com os limites constantes do mapa.
	is_flash_data   <= i_flag_flash when flags_registered else
	                   '1' when unsigned(i_alu_out) < internal_rom_end(rom_end_kib, rom_external) else '0';
	is_sdram        <= i_flag_sdram when flags_registered else
	                   '1' when is_external_addr(unsigned(i_alu_out), rom_end_kib, rom_external, ram_base_kib, ram_end_kib, ram_external, ext_base_kib) else '0';
	is_ram_internal <= (not is_flash_data) and (not is_sdram);

	o_flash_addr2   <= i_alu_out;
	o_flash_rden2   <= i_re_ram and access_valid and is_flash_data;

	o_ram_addr      <= i_alu_out;
	o_ram_wdata     <= i_store_data;
	o_ram_en        <= i_en_ram and access_valid and is_ram_internal;
	o_ram_wren      <= i_we_ram and access_valid and is_ram_internal;
	o_ram_rden      <= i_re_ram and access_valid and is_ram_internal;
	o_ram_byteena   <= i_byte_mask;

	sdram_access    <= access_valid and i_en_ram and is_sdram;
	o_sdram_wait    <= sdram_access and (not i_sdram_ready);
	o_sdram_addr    <= i_alu_out;
	o_sdram_wdata   <= i_store_data;
	o_sdram_byteena <= i_byte_mask;
	o_sdram_wren    <= i_we_ram and sdram_access;
	o_sdram_rden    <= i_re_ram and sdram_access;

end architecture rtl;
