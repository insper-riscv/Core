-- =============================================================================
-- Unidade de acesso desalinhado que cruza a palavra (extensão Zicclsm)
--
-- Executa em duas etapas, no estágio MEM, o load ou store que ocupa duas
-- palavras de 32 bits da memória principal: LW e SW nos offsets 1 a 3, e LH,
-- LHU e SH no offset 3. O acesso é dividido em:
--
--   Etapa 1 (i_valid com o_second = '0'): endereço da palavra que contém o
--     primeiro byte, com os bytes do dado e da máscara que cabem nela. O
--     pipeline fica parado (o_stall = '1') até a etapa concluir.
--   Etapa 2 (o_second = '1'): endereço da palavra seguinte (primeira + 4), com
--     os bytes restantes. A instrução sai do estágio MEM quando o pipeline
--     avança, como qualquer acesso alinhado.
--
-- A etapa 1 conclui quando o escravo está pronto (a RAM interna responde em um
-- ciclo e a SDRAM, quando i_ready = '1') e a memória avança (i_advance = '1').
-- O dado lido da etapa 1 chega ao ciclo seguinte e é guardado em o_first_word
-- durante a etapa 2; o dado lido da etapa 2 chega no estágio WB, onde o
-- stage_wb o junta com o_first_word.
--
-- Loads e stores que não cruzam a palavra passam sem alteração (o_cross = '0').
-- O store chega ao estágio MEM já deslocado pelo store_manager: o SW traz o
-- registrador inteiro e o SH no offset 3 traz a meia palavra em [31:16].
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.byte_mask_consts.all;
use work.ext_ram_consts.all;
use work.mem_map_consts.all;

entity misaligned_unit is
	generic (
		-- Executa em hardware o acesso desalinhado à memória principal (extensão Zicclsm); '0' desliga a unidade.
		has_zicclsm  : boolean := true;
		-- Mapa da plataforma sdram: FLASH, SDRAM e periféricos saem todos pela porta externa (bits 31, 30 ou 29).
		ext_flash    : boolean := false
	);
	port (
		-- Sinal de clock principal.
		i_clk        : in  std_logic;
		-- Reset assíncrono ativo em '1'.
		i_rst        : in  std_logic;
		-- Bit de validade da instrução no estágio MEM.
		i_valid      : in  std_logic;
		-- Habilitação geral de acesso à memória da instrução em MEM.
		i_en         : in  std_logic;
		-- A instrução em MEM é um load.
		i_re         : in  std_logic;
		-- A instrução em MEM é um store.
		i_we         : in  std_logic;
		-- Operação de extensão do load em MEM (EXT_RAM_LW, EXT_RAM_LH, EXT_RAM_LHU, EXT_RAM_LB, EXT_RAM_LBU).
		i_ext_op     : in  ext_ram_op_t;
		-- Máscara de bytes do store em MEM, como saiu do store_manager.
		i_byte_mask  : in  byte_mask_t;
		-- Endereço efetivo do acesso em MEM.
		i_addr       : in  word_t;
		-- Dado do store em MEM, como saiu do store_manager.
		i_store_data : in  word_t;
		-- Sinaliza que o escravo externo SDRAM concluiu a transação atual.
		i_ready      : in  std_logic;
		-- A memória avança neste ciclo (o pipeline não está parado por multdiv nem por espera da SDRAM).
		i_advance    : in  std_logic;
		-- O pipeline avança neste ciclo e a instrução deixa o estágio MEM.
		i_base_run   : in  std_logic;
		-- Palavra lida da RAM interna.
		i_ram_rdata  : in  word_t;
		-- Palavra lida da SDRAM.
		i_sdram_rdata : in word_t;
		-- A instrução em MEM cruza a palavra e é executada por esta unidade.
		o_cross      : out std_logic;
		-- Estamos na etapa 1 de um acesso que cruza: o pipeline deve esperar.
		o_stall      : out std_logic;
		-- Endereço da etapa corrente (palavra da etapa 1 ou palavra seguinte na etapa 2).
		o_addr       : out word_t;
		-- Dado de escrita da etapa corrente.
		o_data       : out word_t;
		-- Máscara de bytes da etapa corrente (zero em loads).
		o_mask       : out byte_mask_t;
		-- Palavra lida na etapa 1, retida para o estágio WB.
		o_first_word : out word_t
	);
end entity misaligned_unit;

architecture rtl of misaligned_unit is

	-- Dois bits menos significativos do endereço efetivo: posição do primeiro byte na palavra.
	signal offset         : byte_offset_t;
	-- Load que ocupa duas palavras (LW fora do offset 0, LH ou LHU no offset 3).
	signal load_cross     : std_logic;
	-- Store que ocupa duas palavras (SW fora do offset 0, SH no offset 3).
	signal store_cross    : std_logic;
	-- O acesso cruza a palavra e a unidade está ligada.
	signal cross          : std_logic;
	-- O endereço pertence à janela da SDRAM.
	signal is_sdram       : std_logic;
	-- A etapa corrente pode concluir: a RAM sempre, a SDRAM quando o escravo está pronto.
	signal step_ok        : std_logic;
	-- '1' durante a etapa 2.
	signal second         : std_logic;
	-- A etapa 1 conclui neste ciclo.
	signal first_done     : std_logic;
	-- Habilita a mudança de etapa.
	signal second_enable  : std_logic;
	-- Dado do store ajustado para 32 bits, sem o deslocamento do store_manager.
	signal raw_data       : word_t;
	-- Máscara de bytes do store sem deslocamento (1111 para SW, 0011 para SH).
	signal raw_mask       : byte_mask_t;
	-- Dado do store posicionado no par de palavras (etapa 2 nos bits [63:32]).
	signal data64         : std_logic_vector(63 downto 0);
	-- Máscara do store posicionada no par de palavras (etapa 2 nos bits [7:4]).
	signal mask8          : std_logic_vector(7 downto 0);
	-- Palavra seguinte à do primeiro byte.
	signal next_word      : unsigned(29 downto 0);
	-- Palavra lida pela região do acesso, a ser guardada na etapa 2.
	signal region_rdata   : word_t;

begin

	offset <= i_addr(1 downto 0);

	load_cross <= '1' when (i_re = '1' and
	                        ((i_ext_op = EXT_RAM_LW and offset /= BYTE_OFFSET_0) or
	                         ((i_ext_op = EXT_RAM_LH or i_ext_op = EXT_RAM_LHU) and offset = BYTE_OFFSET_3)))
	              else '0';

	store_cross <= '1' when (i_we = '1' and
	                         ((i_byte_mask = BYTE_MASK_WORD and offset /= BYTE_OFFSET_0) or
	                          (i_byte_mask = BYTE_MASK_HALF_HIGH and offset = BYTE_OFFSET_3)))
	               else '0';

	cross <= (i_valid and i_en and (load_cross or store_cross)) when has_zicclsm else '0';

	is_sdram <= '1' when ((ext_flash and (i_addr(31) = '1' or i_addr(30) = '1' or i_addr(29) = '1')) or
	                      ((not ext_flash) and unsigned(i_addr) >= SDRAM_BASE_BYTES))
	            else '0';
	step_ok  <= '1' when (is_sdram = '0' or i_ready = '1') else '0';

	first_done    <= cross and (not second) and step_ok and i_advance;
	second_enable <= first_done or (second and i_base_run);

	u_second_ff : entity work.flip_flop
		port map (
			i_d      => first_done,
			o_d      => second,
			i_enable => second_enable,
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	raw_data <= i_store_data when i_byte_mask = BYTE_MASK_WORD else x"0000" & i_store_data(31 downto 16);
	raw_mask <= BYTE_MASK_WORD when i_byte_mask = BYTE_MASK_WORD else BYTE_MASK_HALF_LOW;

	data64 <= std_logic_vector(shift_left(unsigned(x"00000000" & raw_data), 8 * to_integer(unsigned(offset))));
	mask8  <= std_logic_vector(shift_left(unsigned("0000" & raw_mask), to_integer(unsigned(offset))));

	next_word <= unsigned(i_addr(31 downto 2)) + 1;

	o_cross <= cross;
	o_stall <= cross and (not second);
	o_addr  <= i_addr when second = '0' else std_logic_vector(next_word) & BYTE_OFFSET_0;
	o_data  <= data64(31 downto 0) when second = '0' else data64(63 downto 32);
	o_mask  <= BYTE_MASK_NONE when i_we = '0' else
	           mask8(3 downto 0) when second = '0' else
	           mask8(7 downto 4);

	region_rdata <= i_sdram_rdata when is_sdram = '1' else i_ram_rdata;

	u_first_word_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => second,
			i_d      => region_rdata,
			o_d      => o_first_word
		);

end architecture rtl;
