-- =============================================================================
-- Registrador de estágio EX/MEM do pipeline RV32IM de 5 estágios
--
-- Captura, na borda de subida de i_clk, o resultado calculado no estágio EX
-- (ULA, MulDiv ou CSR), o dado e a máscara de bytes preparados pelo
-- StoreManager, o endereço do registrador destino rd e os sinais de controle
-- de memória e write-back, disponibilizando-os ao estágio MEM.
--
-- Prioridade dos controles síncronos:
--   1. i_rst = '1' ou i_flush = '1' -> zera todos os controles e dados e marca
--                                      o pacote como bolha (o_valid = '0').
--   2. i_en = '1'                   -> captura as entradas normalmente.
--   3. i_en = '0'                   -> mantém o estado atual (stall).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

entity reg_ex_mem is

	port (
		-- Sinal de clock.
		i_clk        : in  std_logic;
		-- Sinal de reset síncrono ativo em '1'.
		i_rst        : in  std_logic;
		-- Habilita a atualização do registrador EX/MEM ('1' = avança, '0' = congela).
		i_en         : in  std_logic;
		-- Limpa o registrador injetando bolha ('1' = flush por exceção ou espera de FENCE.I).
		i_flush      : in  std_logic;
		-- Validade da instrução vinda do estágio EX.
		i_valid      : in  std_logic;
		-- PC da instrução vinda do estágio EX (vira o mepc se o acesso à memória gerar exceção).
		i_pc         : in  word_t;
		-- Campo funct3 da instrução vinda do estágio EX (tamanho e sinal do acesso à memória).
		i_funct3     : in  funct3_t;
		-- Resultado final do estágio EX (endereço de memória ou resultado de operação).
		i_alu_out    : in  word_t;
		-- Dado alinhado para escrita em memória vindo do StoreManager.
		i_store_data : in  word_t;
		-- Máscara de habilitação de bytes para escrita na RAM vinda do StoreManager.
		i_byte_mask  : in  byte_mask_t;
		-- Endereço do registrador destino rd.
		i_rd         : in  reg_t;
		-- Habilita escrita no banco de registradores no estágio WB.
		i_we_reg     : in  std_logic;
		-- Habilita escrita na memória de dados no estágio MEM.
		i_we_ram     : in  std_logic;
		-- Habilita leitura da memória de dados no estágio MEM.
		i_re_ram     : in  std_logic;
		-- Habilita acesso à memória de dados no estágio MEM.
		i_en_ram     : in  std_logic;
		-- Modo de extensão de leitura da memória de dados.
		i_ext_ram_op : in  ext_ram_op_t;
		-- Seletor da fonte de escrita no estágio WB.
		i_wb_sel     : in  wb_sel_t;
		-- Validade da instrução registrada no estágio MEM.
		o_valid      : out std_logic;
		-- Resultado do estágio EX registrado para o estágio MEM (e adiantamento EX/MEM).
		o_alu_out    : out word_t;
		-- Dado de escrita alinhado registrado para o estágio MEM.
		o_store_data : out word_t;
		-- Máscara de bytes registrada para o estágio MEM.
		o_byte_mask  : out byte_mask_t;
		-- Endereço de rd registrado para o estágio MEM (e Forwarding Unit).
		o_rd         : out reg_t;
		-- Habilitação de escrita em registrador registrada para o estágio MEM.
		o_we_reg     : out std_logic;
		-- Habilitação de escrita na RAM registrada para o estágio MEM.
		o_we_ram     : out std_logic;
		-- Habilitação de leitura da RAM registrada para o estágio MEM.
		o_re_ram     : out std_logic;
		-- Habilitação de acesso à RAM registrada para o estágio MEM.
		o_en_ram     : out std_logic;
		-- Modo de extensão de leitura da RAM registrado para o estágio MEM.
		o_ext_ram_op : out ext_ram_op_t;
		-- Seletor de write-back registrado para o estágio MEM.
		o_wb_sel     : out wb_sel_t;
		-- PC da instrução registrado para o estágio MEM.
		o_pc         : out word_t;
		-- Campo funct3 registrado para o estágio MEM.
		o_funct3     : out funct3_t
	);

end entity reg_ex_mem;

architecture rtl of reg_ex_mem is

	-- Bit de validade armazenado no registrador EX/MEM.
	signal r_valid      : std_logic    := '0';
	-- PC da instrução armazenado.
	signal r_pc         : word_t       := (others => '0');
	-- Campo funct3 armazenado.
	signal r_funct3     : funct3_t     := (others => '0');
	-- Resultado do estágio EX armazenado.
	signal r_alu_out    : word_t       := (others => '0');
	-- Dado de escrita em memória armazenado.
	signal r_store_data : word_t       := (others => '0');
	-- Máscara de bytes armazenada.
	signal r_byte_mask  : byte_mask_t  := (others => '0');
	-- Endereço de rd armazenado.
	signal r_rd         : reg_t        := (others => '0');
	-- Habilitação de escrita em registrador armazenada.
	signal r_we_reg     : std_logic    := '0';
	-- Habilitação de escrita na RAM armazenada.
	signal r_we_ram     : std_logic    := '0';
	-- Habilitação de leitura da RAM armazenada.
	signal r_re_ram     : std_logic    := '0';
	-- Habilitação de acesso à RAM armazenada.
	signal r_en_ram     : std_logic    := '0';
	-- Modo de extensão da RAM armazenado.
	signal r_ext_ram_op : ext_ram_op_t := (others => '0');
	-- Seletor de write-back armazenado.
	signal r_wb_sel     : wb_sel_t     := (others => '0');

begin

	process(i_clk)
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' or i_flush = '1' then
				r_valid      <= '0';
				r_pc         <= (others => '0');
				r_funct3     <= (others => '0');
				r_alu_out    <= (others => '0');
				r_store_data <= (others => '0');
				r_byte_mask  <= (others => '0');
				r_rd         <= (others => '0');
				r_we_reg     <= '0';
				r_we_ram     <= '0';
				r_re_ram     <= '0';
				r_en_ram     <= '0';
				r_ext_ram_op <= (others => '0');
				r_wb_sel     <= (others => '0');
			elsif i_en = '1' then
				r_valid      <= i_valid;
				r_pc         <= i_pc;
				r_funct3     <= i_funct3;
				r_alu_out    <= i_alu_out;
				r_store_data <= i_store_data;
				r_byte_mask  <= i_byte_mask;
				r_rd         <= i_rd;
				r_we_reg     <= i_we_reg;
				r_we_ram     <= i_we_ram;
				r_re_ram     <= i_re_ram;
				r_en_ram     <= i_en_ram;
				r_ext_ram_op <= i_ext_ram_op;
				r_wb_sel     <= i_wb_sel;
			end if;
		end if;
	end process;

	o_valid      <= r_valid;
	o_pc         <= r_pc;
	o_funct3     <= r_funct3;
	o_alu_out    <= r_alu_out;
	o_store_data <= r_store_data;
	o_byte_mask  <= r_byte_mask;
	o_rd         <= r_rd;
	o_we_reg     <= r_we_reg;
	o_we_ram     <= r_we_ram;
	o_re_ram     <= r_re_ram;
	o_en_ram     <= r_en_ram;
	o_ext_ram_op <= r_ext_ram_op;
	o_wb_sel     <= r_wb_sel;

end architecture rtl;
