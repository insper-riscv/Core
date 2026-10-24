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
use work.mem_map_consts.all;

entity stage_wb is
	port (
		-- Bit de validade da instrução no estágio WB.
		i_valid        : in  std_logic;
		-- Valor PC + 4 da instrução no estágio WB.
		i_pc4          : in  word_t;
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
		-- Palavra de dados lida da segunda porta da memória FLASH.
		i_flash_data2  : in  word_t;
		-- Palavra de dados lida da memória RAM interna.
		i_ram_rdata    : in  word_t;
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

	-- Indica que o endereço de load em WB aponta para a memória FLASH.
	signal is_flash_data_wb : std_logic;
	-- Indica que o endereço de load em WB aponta para o barramento externo de SDRAM.
	signal is_sdram_wb      : std_logic;
	-- Palavra bruta de 32 bits selecionada entre FLASH, SDRAM e RAM interna.
	signal mem_read_data    : word_t;
	-- Palavra de 32 bits alinhada e estendida pelo módulo extender_ram.
	signal wb_ram_extended  : word_t;

begin

	is_flash_data_wb <= '1' when unsigned(i_alu_out) < RAM_BASE_BYTES    else '0';
	is_sdram_wb      <= '1' when unsigned(i_alu_out) >= SDRAM_BASE_BYTES else '0';

	mem_read_data    <= i_flash_data2 when is_flash_data_wb = '1' else
	                    i_sdram_rdata when is_sdram_wb      = '1' else
	                    i_ram_rdata;

	u_extender_ram : entity work.extender_ram
		port map (
			i_data        => mem_read_data,
			i_op          => i_ext_ram_op,
			i_byte_offset => i_alu_out(1 downto 0),
			o_data        => wb_ram_extended
		);

	u_mux_wb : entity work.mux_4x1
		generic map (
			data_width => 32
		)
		port map (
			i_d0  => i_alu_out,
			i_d1  => i_pc4,
			i_d2  => wb_ram_extended,
			i_d3  => i_alu_out,
			i_sel => i_wb_sel,
			o_d   => o_wb_data
		);

	o_wb_we <= i_we_reg and i_valid;
	o_wb_rd <= i_rd_idx;

end architecture rtl;
