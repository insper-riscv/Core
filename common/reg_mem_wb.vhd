-- =============================================================================
-- Registrador de estágio MEM/WB do pipeline RV32IM de 5 estágios
--
-- Captura, na borda de subida de i_clk, os metadados e resultados que saem do
-- estágio MEM (PC + 4, resultado da ULA, endereço de rd e sinais de controle de
-- write-back), disponibilizando-os ao estágio WB no ciclo seguinte.
--
-- Observação sobre a leitura da memória de dados:
--   A palavra lida da memória chega diretamente no ciclo WB (leitura síncrona
--   com 1 ciclo de latência), sendo alinhada e estendida pelo ExtenderRAM com
--   base em o_ext_ram_op e nos bits menos significativos o_alu_out(1 downto 0)
--   registrados aqui.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.byte_mask_consts.all;
use work.ext_ram_consts.all;
use work.mem_map_consts.all;

entity reg_mem_wb is
	generic (
		-- Mapa da plataforma sdram: não há FLASH nem RAM internas e o dado vem da porta externa (bits 31, 30 ou 29).
		ext_flash    : boolean := false
	);
	port (
		-- Sinal de clock.
		i_clk        : in  std_logic;
		-- Sinal de reset síncrono ativo em '1'.
		i_rst        : in  std_logic;
		-- Habilita a atualização do registrador MEM/WB ('1' = avança, '0' = congela).
		i_en         : in  std_logic;
		-- Limpa o registrador injetando bolha ('1' = flush quando o estágio MEM aguarda a RAM).
		i_flush      : in  std_logic;
		-- Validade da instrução vinda do estágio MEM.
		i_valid      : in  std_logic;
		-- Resultado calculado no estágio EX (palavra completa para WB e bits [1:0] para o ExtenderRAM).
		i_alu_out    : in  word_t;
		-- Endereço do registrador destino rd.
		i_rd         : in  reg_t;
		-- Habilita escrita no banco de registradores no estágio WB.
		i_we_reg     : in  std_logic;
		-- Modo de extensão de leitura da memória de dados para o ExtenderRAM.
		i_ext_ram_op : in  ext_ram_op_t;
		-- Seletor da fonte de escrita no estágio WB.
		i_wb_sel     : in  wb_sel_t;
		-- Validade da instrução registrada no estágio WB.
		o_valid      : out std_logic;
		-- Resultado do estágio EX registrado para o estágio WB.
		o_alu_out    : out word_t;
		-- Endereço de rd registrado para o estágio WB (banco de registradores e Forwarding Unit).
		o_rd         : out reg_t;
		-- Habilitação de escrita no banco de registradores registrada para o estágio WB.
		o_we_reg     : out std_logic;
		-- Modo de extensão de leitura da RAM registrado para o estágio WB.
		o_ext_ram_op : out ext_ram_op_t;
		-- Seletor de write-back registrado para o estágio WB.
		o_wb_sel     : out wb_sel_t;
		-- O endereço do load registrado pertence à memória FLASH (decodificado na entrada do registrador).
		o_is_flash   : out std_logic;
		-- O endereço do load registrado pertence à janela externa de SDRAM (decodificado na entrada).
		o_is_sdram   : out std_logic;
		-- O load registrado cruza a palavra e usa a primeira palavra retida (decodificado na entrada).
		o_is_cross   : out std_logic
	);

end entity reg_mem_wb;

architecture rtl of reg_mem_wb is

	-- Bit de validade armazenado no registrador MEM/WB.
	signal r_valid      : std_logic    := '0';
	-- Resultado do estágio EX armazenado.
	signal r_alu_out    : word_t       := (others => '0');
	-- Endereço de rd armazenado.
	signal r_rd         : reg_t        := (others => '0');
	-- Habilitação de escrita em registrador armazenada.
	signal r_we_reg     : std_logic    := '0';
	-- Modo de extensão da RAM armazenado.
	signal r_ext_ram_op : ext_ram_op_t := (others => '0');
	-- Seletor de write-back armazenado.
	signal r_wb_sel     : wb_sel_t     := (others => '0');
	-- Endereço na FLASH armazenado.
	signal r_is_flash   : std_logic    := '0';
	-- Endereço na janela de SDRAM armazenado.
	signal r_is_sdram   : std_logic    := '0';
	-- Load com cruzamento de palavra armazenado.
	signal r_is_cross   : std_logic    := '0';
	-- Entrada: o endereço de i_alu_out pertence à FLASH (bits [31:15] em '0').
	signal in_is_flash  : std_logic;
	-- Entrada: o endereço de i_alu_out pertence à janela de SDRAM (bit 31 ou bit 30 em '1').
	signal in_is_sdram  : std_logic;
	-- Entrada: o load cruza a palavra (LW fora de alinhamento ou meia-palavra no byte 3).
	signal in_is_cross  : std_logic;

begin

	-- As fronteiras do mapa são potências de 2, então a região sai de testes de bits do endereço.
	in_is_flash <= '0' when ext_flash else
	               '1' when i_alu_out(PERIPHERAL_BASE_BIT downto RAM_BASE_BIT) = (PERIPHERAL_BASE_BIT downto RAM_BASE_BIT => '0') else '0';
	in_is_sdram <= (i_alu_out(PERIPHERAL_BASE_BIT) or i_alu_out(SDRAM_BASE_BIT) or i_alu_out(FLASH_EXT_BASE_BIT)) when ext_flash else
	               (i_alu_out(PERIPHERAL_BASE_BIT) or i_alu_out(SDRAM_BASE_BIT));
	in_is_cross <= '1' when ((i_ext_ram_op = EXT_RAM_LW and i_alu_out(1 downto 0) /= BYTE_OFFSET_0) or
	                         ((i_ext_ram_op = EXT_RAM_LH or i_ext_ram_op = EXT_RAM_LHU) and i_alu_out(1 downto 0) = BYTE_OFFSET_3))
	               else '0';

	process(i_clk)
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' or i_flush = '1' then
				r_valid      <= '0';
				r_alu_out    <= (others => '0');
				r_rd         <= (others => '0');
				r_we_reg     <= '0';
				r_ext_ram_op <= (others => '0');
				r_wb_sel     <= (others => '0');
				r_is_flash   <= '0';
				r_is_sdram   <= '0';
				r_is_cross   <= '0';
			elsif i_en = '1' then
				r_valid      <= i_valid;
				r_alu_out    <= i_alu_out;
				r_rd         <= i_rd;
				r_we_reg     <= i_we_reg;
				r_ext_ram_op <= i_ext_ram_op;
				r_wb_sel     <= i_wb_sel;
				r_is_flash   <= in_is_flash;
				r_is_sdram   <= in_is_sdram;
				r_is_cross   <= in_is_cross;
			end if;
		end if;
	end process;

	o_valid      <= r_valid;
	o_alu_out    <= r_alu_out;
	o_rd         <= r_rd;
	o_we_reg     <= r_we_reg;
	o_ext_ram_op <= r_ext_ram_op;
	o_wb_sel     <= r_wb_sel;
	o_is_flash   <= r_is_flash;
	o_is_sdram   <= r_is_sdram;
	o_is_cross   <= r_is_cross;

end architecture rtl;
