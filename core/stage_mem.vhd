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
		-- Mapa da plataforma sdram: FLASH, SDRAM e periféricos saem pela porta externa; não há FLASH nem RAM internas.
		ext_flash       : boolean := false
	);
	port (
		-- Bit de validade da instrução no estágio MEM.
		i_valid         : in  std_logic;
		-- Endereço apresentado às memórias neste ciclo (o efetivo, ou o da segunda palavra de um acesso que cruza).
		i_alu_out       : in  word_t;
		-- Endereço efetivo original do load ou store, vindo do registrador EX/MEM.
		i_ea            : in  word_t;
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
			has_zicclsm => has_zicclsm,
			check_ea    => check_ea,
			ext_flash   => ext_flash
		)
		port map (
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

	assert RAM_BASE_BYTES = x"00008000" and SDRAM_BASE_BYTES = x"40000000"
		report "O stage_mem decodifica as regiões por bits do endereço: RAM_BASE e SDRAM_BASE devem ser 2**15 e 2**30"
		severity failure;

	-- As fronteiras do mapa são potências de 2, então a região sai de testes de bits do endereço.
	is_flash_data   <= '0' when ext_flash else
	                   '1' when i_alu_out(31 downto 15) = (31 downto 15 => '0') else '0';
	is_sdram        <= (i_alu_out(31) or i_alu_out(30) or i_alu_out(29)) when ext_flash else
	                   (i_alu_out(31) or i_alu_out(30));
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
