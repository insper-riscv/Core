-- =============================================================================
-- Registrador de estágio ID/EX do pipeline RV32IM de 5 estágios
--
-- Captura, na borda de subida de i_clk, os operandos lidos do banco de
-- registradores, o imediato estendido, os endereços de registradores e os
-- sinais de controle decodificados no estágio ID, disponibilizando-os ao
-- estágio EX no ciclo seguinte.
--
-- Prioridade dos controles síncronos:
--   1. i_rst = '1' ou i_flush = '1' -> zera todos os sinais de controle e dados
--                                      e marca o pacote como bolha (o_valid = '0').
--   2. i_en = '1'                   -> captura as entradas normalmente.
--   3. i_en = '0'                   -> mantém o estado atual (stall).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

entity reg_id_ex is

	port (
		-- Sinal de clock.
		i_clk         : in  std_logic;
		-- Sinal de reset síncrono ativo em '1'.
		i_rst         : in  std_logic;
		-- Habilita a atualização do registrador ID/EX ('1' = avança, '0' = congela).
		i_en          : in  std_logic;
		-- Limpa o registrador injetando bolha ('1' = flush por desvio/trap).
		i_flush       : in  std_logic;
		-- Validade da instrução vinda do estágio ID.
		i_valid       : in  std_logic;
		-- Endereço PC da instrução no estágio ID.
		i_pc          : in  word_t;
		-- Valor de PC + 4 da instrução no estágio ID.
		i_pc4         : in  word_t;
		-- Endereço do registrador fonte rs1.
		i_rs1         : in  reg_t;
		-- Endereço do registrador fonte rs2.
		i_rs2         : in  reg_t;
		-- Endereço do registrador destino rd.
		i_rd          : in  reg_t;
		-- Valor lido da porta rs1 do banco de registradores.
		i_rs1_val     : in  word_t;
		-- Valor lido da porta rs2 do banco de registradores.
		i_rs2_val     : in  word_t;
		-- Imediato de 32 bits estendido no estágio ID.
		i_imm         : in  word_t;
		-- Indica salto incondicional (JAL / JALR) vindo da unidade de controle.
		i_sel_pc4_alu : in  std_logic;
		-- Seletor da fonte de escrita no estágio WB.
		i_wb_sel      : in  wb_sel_t;
		-- Habilita escrita no banco de registradores (pós-bubble_mux).
		i_we_reg      : in  std_logic;
		-- Modo de extensão de leitura da memória de dados.
		i_ext_ram_op  : in  ext_ram_op_t;
		-- Seleciona o operando B da ULA ('0' = rs2, '1' = imediato).
		i_sel_rs2_imm : in  std_logic;
		-- Seleciona o operando A da ULA ('0' = PC, '1' = rs1).
		i_sel_pc_rs1  : in  std_logic;
		-- Código de operação da ULA.
		i_alu_op      : in  alu_op_t;
		-- Indica instrução pertencente à extensão M (MulDiv).
		i_is_muldiv   : in  std_logic;
		-- Indica instrução pertencente à extensão Zicsr (acesso a registrador CSR).
		i_is_csr      : in  std_logic := '0';
		-- Habilita escrita na memória de dados (pós-bubble_mux).
		i_we_ram      : in  std_logic;
		-- Habilita leitura da memória de dados (pós-bubble_mux).
		i_re_ram      : in  std_logic;
		-- Habilita acesso à memória de dados (pós-bubble_mux).
		i_en_ram      : in  std_logic;
		-- Campo opcode da instrução.
		i_opcode      : in  opcode_t;
		-- Campo funct3 da instrução.
		i_funct3      : in  funct3_t;
		-- Validade da instrução registrada no estágio EX.
		o_valid       : out std_logic;
		-- Endereço PC registrado para o estágio EX.
		o_pc          : out word_t;
		-- Valor de PC + 4 registrado para o estágio EX.
		o_pc4         : out word_t;
		-- Endereço de rs1 registrado para o estágio EX (usado pela Forwarding Unit).
		o_rs1         : out reg_t;
		-- Endereço de rs2 registrado para o estágio EX (usado pela Forwarding Unit).
		o_rs2         : out reg_t;
		-- Endereço de rd registrado para o estágio EX (usado pela HDU e estágios seguintes).
		o_rd          : out reg_t;
		-- Valor de rs1 registrado para o estágio EX.
		o_rs1_val     : out word_t;
		-- Valor de rs2 registrado para o estágio EX.
		o_rs2_val     : out word_t;
		-- Imediato estendido registrado para o estágio EX.
		o_imm         : out word_t;
		-- Sinal de salto incondicional registrado para o estágio EX.
		o_sel_pc4_alu : out std_logic;
		-- Seletor de write-back registrado para o estágio EX.
		o_wb_sel      : out wb_sel_t;
		-- Habilitação de escrita no banco de registradores registrada para o estágio EX.
		o_we_reg      : out std_logic;
		-- Modo de extensão de leitura da RAM registrado para o estágio EX.
		o_ext_ram_op  : out ext_ram_op_t;
		-- Seletor do operando B da ULA registrado para o estágio EX.
		o_sel_rs2_imm : out std_logic;
		-- Seletor do operando A da ULA registrado para o estágio EX.
		o_sel_pc_rs1  : out std_logic;
		-- Código de operação da ULA registrado para o estágio EX.
		o_alu_op      : out alu_op_t;
		-- Indicador de instrução MulDiv registrado para o estágio EX.
		o_is_muldiv   : out std_logic;
		-- Indicador de instrução CSR registrado para o estágio EX.
		o_is_csr      : out std_logic;
		-- Habilitação de escrita na RAM registrada para o estágio EX.
		o_we_ram      : out std_logic;
		-- Habilitação de leitura da RAM registrada para o estágio EX.
		o_re_ram      : out std_logic;
		-- Habilitação de acesso à RAM registrada para o estágio EX.
		o_en_ram      : out std_logic;
		-- Campo opcode registrado para o estágio EX.
		o_opcode      : out opcode_t;
		-- Campo funct3 registrado para o estágio EX.
		o_funct3      : out funct3_t
	);

end entity reg_id_ex;

architecture rtl of reg_id_ex is

	-- Bit de validade armazenado no registrador ID/EX.
	signal r_valid       : std_logic    := '0';
	-- Endereço PC armazenado.
	signal r_pc          : word_t       := (others => '0');
	-- Valor de PC + 4 armazenado.
	signal r_pc4         : word_t       := (others => '0');
	-- Endereço de rs1 armazenado.
	signal r_rs1         : reg_t        := (others => '0');
	-- Endereço de rs2 armazenado.
	signal r_rs2         : reg_t        := (others => '0');
	-- Endereço de rd armazenado.
	signal r_rd          : reg_t        := (others => '0');
	-- Valor de rs1 armazenado.
	signal r_rs1_val     : word_t       := (others => '0');
	-- Valor de rs2 armazenado.
	signal r_rs2_val     : word_t       := (others => '0');
	-- Imediato estendido armazenado.
	signal r_imm         : word_t       := (others => '0');
	-- Sinal de salto incondicional armazenado.
	signal r_sel_pc4_alu : std_logic    := '0';
	-- Seletor de write-back armazenado.
	signal r_wb_sel      : wb_sel_t     := (others => '0');
	-- Habilitação de escrita em registrador armazenada.
	signal r_we_reg      : std_logic    := '0';
	-- Modo de extensão da RAM armazenado.
	signal r_ext_ram_op  : ext_ram_op_t := (others => '0');
	-- Seletor de operando B da ULA armazenado.
	signal r_sel_rs2_imm : std_logic    := '0';
	-- Seletor de operando A da ULA armazenado.
	signal r_sel_pc_rs1  : std_logic    := '0';
	-- Código de operação da ULA armazenado.
	signal r_alu_op      : alu_op_t     := (others => '0');
	-- Indicador de instrução MulDiv armazenado.
	signal r_is_muldiv   : std_logic    := '0';
	-- Indicador de instrução CSR armazenado.
	signal r_is_csr      : std_logic    := '0';
	-- Habilitação de escrita na RAM armazenada.
	signal r_we_ram      : std_logic    := '0';
	-- Habilitação de leitura da RAM armazenada.
	signal r_re_ram      : std_logic    := '0';
	-- Habilitação de acesso à RAM armazenada.
	signal r_en_ram      : std_logic    := '0';
	-- Campo opcode armazenado.
	signal r_opcode      : opcode_t     := (others => '0');
	-- Campo funct3 armazenado.
	signal r_funct3      : funct3_t     := (others => '0');

begin

	process(i_clk)
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' or i_flush = '1' then
				r_valid       <= '0';
				r_pc          <= (others => '0');
				r_pc4         <= (others => '0');
				r_rs1         <= (others => '0');
				r_rs2         <= (others => '0');
				r_rd          <= (others => '0');
				r_rs1_val     <= (others => '0');
				r_rs2_val     <= (others => '0');
				r_imm         <= (others => '0');
				r_sel_pc4_alu <= '0';
				r_wb_sel      <= (others => '0');
				r_we_reg      <= '0';
				r_ext_ram_op  <= (others => '0');
				r_sel_rs2_imm <= '0';
				r_sel_pc_rs1  <= '0';
				r_alu_op      <= (others => '0');
				r_is_muldiv   <= '0';
				r_is_csr      <= '0';
				r_we_ram      <= '0';
				r_re_ram      <= '0';
				r_en_ram      <= '0';
				r_opcode      <= (others => '0');
				r_funct3      <= (others => '0');
			elsif i_en = '1' then
				r_valid       <= i_valid;
				r_pc          <= i_pc;
				r_pc4         <= i_pc4;
				r_rs1         <= i_rs1;
				r_rs2         <= i_rs2;
				r_rd          <= i_rd;
				r_rs1_val     <= i_rs1_val;
				r_rs2_val     <= i_rs2_val;
				r_imm         <= i_imm;
				r_sel_pc4_alu <= i_sel_pc4_alu;
				r_wb_sel      <= i_wb_sel;
				r_we_reg      <= i_we_reg;
				r_ext_ram_op  <= i_ext_ram_op;
				r_sel_rs2_imm <= i_sel_rs2_imm;
				r_sel_pc_rs1  <= i_sel_pc_rs1;
				r_alu_op      <= i_alu_op;
				r_is_muldiv   <= i_is_muldiv;
				r_is_csr      <= i_is_csr;
				r_we_ram      <= i_we_ram;
				r_re_ram      <= i_re_ram;
				r_en_ram      <= i_en_ram;
				r_opcode      <= i_opcode;
				r_funct3      <= i_funct3;
			end if;
		end if;
	end process;

	o_valid       <= r_valid;
	o_pc          <= r_pc;
	o_pc4         <= r_pc4;
	o_rs1         <= r_rs1;
	o_rs2         <= r_rs2;
	o_rd          <= r_rd;
	o_rs1_val     <= r_rs1_val;
	o_rs2_val     <= r_rs2_val;
	o_imm         <= r_imm;
	o_sel_pc4_alu <= r_sel_pc4_alu;
	o_wb_sel      <= r_wb_sel;
	o_we_reg      <= r_we_reg;
	o_ext_ram_op  <= r_ext_ram_op;
	o_sel_rs2_imm <= r_sel_rs2_imm;
	o_sel_pc_rs1  <= r_sel_pc_rs1;
	o_alu_op      <= r_alu_op;
	o_is_muldiv   <= r_is_muldiv;
	o_is_csr      <= r_is_csr;
	o_we_ram      <= r_we_ram;
	o_re_ram      <= r_re_ram;
	o_en_ram      <= r_en_ram;
	o_opcode      <= r_opcode;
	o_funct3      <= r_funct3;

end architecture rtl;
