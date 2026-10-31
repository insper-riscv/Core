-- =============================================================================
-- Estágio MEM (Memory Access) do Pipeline RV32
--
-- Decodifica o endereço efetivo calculado no estágio EX (i_alu_out) usando as
-- constantes centralizadas em mem_map_consts e roteia os sinais de leitura,
-- escrita e máscara de bytes para os três subsistemas de memória de dados:
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

entity stage_mem is
	port (
		-- Bit de validade da instrução no estágio MEM.
		i_valid         : in  std_logic;
		-- Endereço efetivo de memória (ou resultado da ULA) vindo do registrador EX/MEM.
		i_alu_out       : in  word_t;
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
		o_sdram_wait    : out std_logic
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

begin

	is_flash_data   <= '1' when unsigned(i_alu_out) < RAM_BASE_BYTES    else '0';
	is_sdram        <= '1' when unsigned(i_alu_out) >= SDRAM_BASE_BYTES else '0';
	is_ram_internal <= (not is_flash_data) and (not is_sdram);

	o_flash_addr2   <= i_alu_out;
	o_flash_rden2   <= i_re_ram and i_valid and is_flash_data;

	o_ram_addr      <= i_alu_out;
	o_ram_wdata     <= i_store_data;
	o_ram_en        <= i_en_ram and i_valid and is_ram_internal;
	o_ram_wren      <= i_we_ram and i_valid and is_ram_internal;
	o_ram_rden      <= i_re_ram and i_valid and is_ram_internal;
	o_ram_byteena   <= i_byte_mask;

	sdram_access    <= i_valid and i_en_ram and is_sdram;
	o_sdram_wait    <= sdram_access and (not i_sdram_ready);
	o_sdram_addr    <= i_alu_out;
	o_sdram_wdata   <= i_store_data;
	o_sdram_byteena <= i_byte_mask;
	o_sdram_wren    <= i_we_ram and sdram_access;
	o_sdram_rden    <= i_re_ram and sdram_access;

end architecture rtl;
