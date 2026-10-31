-- =============================================================================
-- Estágio WB (Write-Back) do Pipeline RV32
--
-- Seleciona a palavra bruta retornada pelo subsistema de memória acessado no
-- ciclo anterior (FLASH porta 2, RAM interna ou SDRAM externa) usando as
-- constantes centralizadas em mem_map_consts, aplica o alinhamento e extensão
-- de sinal/zero para instruções de load (extender_ram) e seleciona o dado
-- final a ser gravado no banco de registradores (mux_4x1).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.byte_mask_consts.all;
use work.mem_map_consts.all;
use work.ext_ram_consts.all;

entity stage_wb is
	port (
		-- Bit de validade da instrução no estágio WB.
		i_valid        : in  std_logic;
		-- Resultado da ULA/execução (e bits [1:0] do endereço de load) no estágio WB.
		i_alu_out      : in  word_t;
		-- Índice do registrador destino rd no estágio WB.
		i_rd_idx       : in  reg_t;
		-- Habilitação de escrita no banco de registradores vinda do registrador MEM/WB.
		i_we_reg       : in  std_logic;
		-- Modo de extensão de leitura da memória de dados vindo do registrador MEM/WB.
		i_ext_ram_op   : in  ext_ram_op_t;
		-- Seletor de fonte de Write-Back vindo do registrador MEM/WB.
		i_wb_sel       : in  wb_sel_t;
		-- O endereço do load pertence à memória FLASH (decodificado no registrador MEM/WB).
		i_is_flash     : in  std_logic;
		-- O endereço do load pertence ao barramento externo de SDRAM (decodificado no registrador MEM/WB).
		i_is_sdram     : in  std_logic;
		-- O load cruza a palavra e usa a primeira palavra retida (decodificado no registrador MEM/WB).
		i_is_cross     : in  std_logic;
		-- Palavra de dados lida da segunda porta da memória FLASH.
		i_flash_data2  : in  word_t;
		-- Palavra de dados lida da memória RAM interna.
		i_ram_rdata    : in  word_t;
		-- Primeira palavra de um load desalinhado que cruzou a palavra, retida pela misaligned_unit.
		i_first_word   : in  word_t;
		-- Palavra de dados lida do barramento externo SDRAM.
		i_sdram_rdata  : in  word_t;
		-- Habilitação final de escrita enviada ao banco de registradores (reg_file).
		o_wb_we        : out std_logic;
		-- Endereço final do registrador destino rd enviado ao banco de registradores.
		o_wb_rd        : out reg_t;
		-- Dado final de 32 bits enviado ao banco de registradores e à malha de forwarding.
		o_wb_data      : out word_t
	);
end entity stage_wb;

architecture rtl of stage_wb is

	-- Palavra bruta de 32 bits selecionada entre FLASH, SDRAM e RAM interna.
	signal mem_read_data    : word_t;
	-- Palavra de 32 bits alinhada e estendida pelo módulo extender_ram.
	signal wb_ram_extended  : word_t;
	-- Par de palavras do load que cruzou, deslocado até o primeiro byte do dado.
	signal cross_pair       : std_logic_vector(63 downto 0);
	-- Palavra baixa do par deslocado: o dado do load alinhado ao byte 0.
	signal cross_word       : word_t;
	-- Palavra entregue ao extensor: a juntada de duas palavras ou a lida da memória.
	signal ext_data         : word_t;
	-- Posição do dado dentro da palavra entregue ao extensor.
	signal ext_offset       : byte_offset_t;

begin

	mem_read_data    <= i_flash_data2 when i_is_flash = '1' else
	                    i_sdram_rdata when i_is_sdram = '1' else
	                    i_ram_rdata;

	cross_pair <= std_logic_vector(shift_right(unsigned(mem_read_data & i_first_word),
	                                           8 * to_integer(unsigned(i_alu_out(1 downto 0)))));
	cross_word <= cross_pair(31 downto 0);

	ext_data   <= cross_word when i_is_cross = '1' else mem_read_data;
	ext_offset <= BYTE_OFFSET_0 when i_is_cross = '1' else i_alu_out(1 downto 0);

	u_extender_ram : entity work.extender_ram
		port map (
			i_data        => ext_data,
			i_op          => i_ext_ram_op,
			i_byte_offset => ext_offset,
			o_data        => wb_ram_extended
		);

	u_mux_wb : entity work.mux_2x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => i_alu_out,
			i_d1  => wb_ram_extended,
			i_sel => i_wb_sel(0),
			o_d   => o_wb_data
		);

	o_wb_we <= i_we_reg and i_valid;
	o_wb_rd <= i_rd_idx;

end architecture rtl;
