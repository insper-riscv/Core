-- =============================================================================
-- Banco de registradores de controle e estado (CSRs) do Modo Máquina (Extensão Zicsr)
--
-- Implementa a leitura combinacional (o_rdata) e a atualização atômica dos CSRs
-- do modo máquina (M-mode) no estágio EX quando i_commit = '1':
--   - Operações suportadas via i_op (funct3):
--     * CSRRW / CSRRWI (bits [1:0] = "01"): escrita direta (new = i_wdata)
--     * CSRRS / CSRRSI (bits [1:0] = "10"): set de bits (new = old or i_wdata)
--     * CSRRC / CSRRCI (bits [1:0] = "11"): clear de bits (new = old and not i_wdata)
--     Nas operações RS e RC, quando i_src_zero = '1' (rs1 = x0 ou zimm = 0),
--     nenhuma escrita efetiva é realizada.
--   - Tratamento de Trap (i_trap_take = '1'): grava mepc, mcause e mtval, copia
--     MIE para MPIE e zera MIE.
--   - Retorno de Trap (i_mret_take = '1'): restaura MIE a partir de MPIE e
--     define MPIE = '1'.
--   - Endereços de CSR inexistentes ou tentativas de escrita efetiva em CSRs
--     somente-leitura (bits [11:10] = "11") assertem o_illegal = '1'.
--
-- Todos os registradores de estado utilizam instâncias estruturais de
-- generic_register e flip_flop.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

entity csr_file is
	port (
		-- Sinal de clock do sistema.
		i_clk        : in  std_logic;
		-- Sinal de reset ativo em '1'.
		i_rst        : in  std_logic;
		-- Habilita a efetivação da escrita de instrução CSR válida no estágio EX.
		i_commit     : in  std_logic;
		-- Endereço de 12 bits do registrador CSR (extraído de instr[31:20]).
		i_addr       : in  std_logic_vector(11 downto 0);
		-- Código funct3 que seleciona o modo da operação CSR (RW, RS, RC).
		i_op         : in  funct3_t;
		-- Dado de 32 bits de entrada para escrita/modificação (rs1 ou imediato zimm).
		i_wdata      : in  word_t;
		-- Indica que o campo fonte rs1/zimm é igual a zero (inibe escrita em RS/RC).
		i_src_zero   : in  std_logic;
		-- Valor atual (antigo) de 32 bits lido combinacionalmente do CSR selecionado.
		o_rdata      : out word_t;
		-- Indica acesso a endereço CSR não implementado ou escrita em CSR somente-leitura.
		o_illegal    : out std_logic;
		-- Pulso que comanda o salvamento de contexto de exceção síncrona no modo máquina.
		i_trap_take  : in  std_logic := '0';
		-- Código da causa da exceção a ser gravado em mcause.
		i_trap_cause : in  word_t    := (others => '0');
		-- Endereço PC da instrução que gerou a exceção a ser gravado em mepc.
		i_trap_pc    : in  word_t    := (others => '0');
		-- Valor informativo de falha (endereço desalinhado ou zero) a ser gravado em mtval.
		i_trap_tval  : in  word_t    := (others => '0');
		-- Pulso que comanda a execução do retorno de exceção (MRET).
		i_mret_take  : in  std_logic := '0';
		-- Endereço base do tratador de traps armazenado no registrador mtvec.
		o_mtvec      : out word_t;
		-- Endereço de retorno de exceção armazenado no registrador mepc.
		o_mepc       : out word_t
	);
end entity csr_file;

architecture rtl of csr_file is

	-- Endereço do CSR mstatus (Machine Status Register).
	constant ADDR_MSTATUS    : std_logic_vector(11 downto 0) := x"300";
	-- Endereço do CSR misa (Machine ISA Register).
	constant ADDR_MISA       : std_logic_vector(11 downto 0) := x"301";
	-- Endereço do CSR mie (Machine Interrupt Enable Register).
	constant ADDR_MIE        : std_logic_vector(11 downto 0) := x"304";
	-- Endereço do CSR mtvec (Machine Trap-Vector Base-Address Register).
	constant ADDR_MTVEC      : std_logic_vector(11 downto 0) := x"305";
	-- Endereço do CSR mstatush (Machine Status Register Upper 32 bits).
	constant ADDR_MSTATUSH   : std_logic_vector(11 downto 0) := x"310";
	-- Endereço do CSR mscratch (Machine Scratch Register).
	constant ADDR_MSCRATCH   : std_logic_vector(11 downto 0) := x"340";
	-- Endereço do CSR mepc (Machine Exception Program Counter).
	constant ADDR_MEPC       : std_logic_vector(11 downto 0) := x"341";
	-- Endereço do CSR mcause (Machine Cause Register).
	constant ADDR_MCAUSE     : std_logic_vector(11 downto 0) := x"342";
	-- Endereço do CSR mtval (Machine Trap Value Register).
	constant ADDR_MTVAL      : std_logic_vector(11 downto 0) := x"343";
	-- Endereço do CSR mip (Machine Interrupt Pending Register).
	constant ADDR_MIP        : std_logic_vector(11 downto 0) := x"344";
	-- Endereço do CSR mvendorid (Machine Vendor ID Register).
	constant ADDR_MVENDORID  : std_logic_vector(11 downto 0) := x"F11";
	-- Endereço do CSR marchid (Machine Architecture ID Register).
	constant ADDR_MARCHID    : std_logic_vector(11 downto 0) := x"F12";
	-- Endereço do CSR mimpid (Machine Implementation ID Register).
	constant ADDR_MIMPID     : std_logic_vector(11 downto 0) := x"F13";
	-- Endereço do CSR mhartid (Hart ID Register).
	constant ADDR_MHARTID    : std_logic_vector(11 downto 0) := x"F14";
	-- Endereço do CSR mconfigptr (Machine Configuration Pointer Register).
	constant ADDR_MCONFIGPTR : std_logic_vector(11 downto 0) := x"F15";

	-- Valor fixo do registrador misa: RV32 (MXL = 1) com extensões I e M habilitadas.
	constant MISA_VALUE      : word_t := x"40001100";

	-- Bit MIE (bit 3) armazenado no registrador mstatus.
	signal mstatus_mie       : std_logic;
	-- Bit MPIE (bit 7) armazenado no registrador mstatus.
	signal mstatus_mpie      : std_logic;
	-- Valor registrado do CSR mtvec.
	signal mtvec_reg         : word_t;
	-- Valor registrado do CSR mscratch.
	signal mscratch_reg      : word_t;
	-- Valor registrado do CSR mepc.
	signal mepc_reg          : word_t;
	-- Valor registrado do CSR mcause.
	signal mcause_reg        : word_t;
	-- Valor registrado do CSR mtval.
	signal mtval_reg         : word_t;

	-- Palavra completa de 32 bits montada a partir dos campos de mstatus (MPP = "11", MPIE, MIE).
	signal mstatus_value     : word_t;
	-- Valor lido combinacionalmente do CSR selecionado por i_addr.
	signal old_value         : word_t;
	-- Novo valor calculado para escrita pela operação CSR (RW, RS ou RC).
	signal new_value         : word_t;
	-- Indica se o endereço i_addr corresponde a um CSR reconhecido pelo hardware.
	signal is_known_addr     : std_logic;
	-- Indica se o endereço i_addr pertence à faixa somente-leitura (bits [11:10] = "11").
	signal is_read_only      : std_logic;
	-- Indica se a instrução CSR produz efeito de escrita (CSRRW ou fonte não nula).
	signal has_write_effect  : std_logic;
	-- Indica que uma escrita normal de instrução CSR deve ser efetivada neste ciclo.
	signal csr_write_valid   : std_logic;

	-- Sinais de habilitação e próximo valor para os flip-flops de mstatus (MIE e MPIE).
	signal mie_we            : std_logic;
	-- Próximo bit a ser gravado em mstatus_mie.
	signal mie_nxt           : std_logic;
	-- Habilitação de escrita do bit mstatus_mpie.
	signal mpie_we           : std_logic;
	-- Próximo bit a ser gravado em mstatus_mpie.
	signal mpie_nxt          : std_logic;

	-- Sinais de habilitação e próximo valor para os registradores CSR de 32 bits.
	signal mtvec_we          : std_logic;
	-- Próximo valor alinhado para escrita em mtvec.
	signal mtvec_nxt         : word_t;
	-- Habilitação de escrita em mscratch.
	signal mscratch_we       : std_logic;
	-- Habilitação de escrita em mepc (por trap ou instrução CSR).
	signal mepc_we           : std_logic;
	-- Próximo valor alinhado para escrita em mepc.
	signal mepc_nxt          : word_t;
	-- Habilitação de escrita em mcause (por trap ou instrução CSR).
	signal mcause_we         : std_logic;
	-- Próximo valor para escrita em mcause.
	signal mcause_nxt        : word_t;
	-- Habilitação de escrita em mtval (por trap ou instrução CSR).
	signal mtval_we          : std_logic;
	-- Próximo valor para escrita em mtval.
	signal mtval_nxt         : word_t;

begin

	-- Montagem da palavra mstatus: MPP (bits [12:11]) fixo em "11" (Machine Mode).
	mstatus_value <= (12 => '1', 11 => '1', 7 => mstatus_mpie, 3 => mstatus_mie, others => '0');

	-- Seleção combinacional de leitura do CSR.
	with i_addr select
		old_value <=
			mstatus_value when ADDR_MSTATUS,
			MISA_VALUE    when ADDR_MISA,
			mtvec_reg     when ADDR_MTVEC,
			mscratch_reg  when ADDR_MSCRATCH,
			mepc_reg      when ADDR_MEPC,
			mcause_reg    when ADDR_MCAUSE,
			mtval_reg     when ADDR_MTVAL,
			(others => '0') when others;

	with i_addr select
		is_known_addr <=
			'1' when ADDR_MSTATUS | ADDR_MISA | ADDR_MIE | ADDR_MTVEC | ADDR_MSTATUSH |
			         ADDR_MSCRATCH | ADDR_MEPC | ADDR_MCAUSE | ADDR_MTVAL | ADDR_MIP |
			         ADDR_MVENDORID | ADDR_MARCHID | ADDR_MIMPID | ADDR_MHARTID | ADDR_MCONFIGPTR,
			'0' when others;

	o_rdata <= old_value;
	o_mtvec <= mtvec_reg;
	o_mepc  <= mepc_reg;

	-- Cálculo do valor modificado conforme os bits [1:0] de i_op (01=RW, 10=RS, 11=RC).
	with i_op(1 downto 0) select
		new_value <=
			i_wdata                     when "01",
			old_value or i_wdata        when "10",
			old_value and (not i_wdata) when others;

	has_write_effect <= '1' when (i_op(1 downto 0) = "01" or i_src_zero = '0') else '0';
	is_read_only     <= '1' when i_addr(11 downto 10) = "11" else '0';
	o_illegal        <= (not is_known_addr) or (has_write_effect and is_read_only);

	csr_write_valid  <= '1' when (i_commit = '1' and has_write_effect = '1' and is_known_addr = '1' and is_read_only = '0') else '0';

	-- Controle de atualização de mstatus.MIE e mstatus.MPIE (prioridade: trap_take > mret_take > escrita CSR).
	mie_we  <= '1' when (i_trap_take = '1' or i_mret_take = '1' or (csr_write_valid = '1' and i_addr = ADDR_MSTATUS)) else '0';
	mie_nxt <= '0'          when i_trap_take = '1' else
	           mstatus_mpie when i_mret_take = '1' else
	           new_value(3);

	mpie_we  <= mie_we;
	mpie_nxt <= mstatus_mie when i_trap_take = '1' else
	            '1'         when i_mret_take = '1' else
	            new_value(7);

	-- Controle de atualização dos CSRs de 32 bits.
	mtvec_we    <= '1' when (csr_write_valid = '1' and i_addr = ADDR_MTVEC and i_trap_take = '0' and i_mret_take = '0') else '0';
	mtvec_nxt   <= new_value(31 downto 2) & "00";

	mscratch_we <= '1' when (csr_write_valid = '1' and i_addr = ADDR_MSCRATCH and i_trap_take = '0' and i_mret_take = '0') else '0';

	mepc_we     <= '1' when (i_trap_take = '1' or (csr_write_valid = '1' and i_addr = ADDR_MEPC and i_mret_take = '0')) else '0';
	mepc_nxt    <= i_trap_pc(31 downto 2) & "00" when i_trap_take = '1' else
	               new_value(31 downto 2) & "00";

	mcause_we   <= '1' when (i_trap_take = '1' or (csr_write_valid = '1' and i_addr = ADDR_MCAUSE and i_mret_take = '0')) else '0';
	mcause_nxt  <= i_trap_cause when i_trap_take = '1' else new_value;

	mtval_we    <= '1' when (i_trap_take = '1' or (csr_write_valid = '1' and i_addr = ADDR_MTVAL and i_mret_take = '0')) else '0';
	mtval_nxt   <= i_trap_tval  when i_trap_take = '1' else new_value;

	-- Instâncias estruturais de flip_flop e generic_register para os CSRs.
	u_mstatus_mie_ff : entity work.flip_flop
		port map (
			i_d      => mie_nxt,
			o_d      => mstatus_mie,
			i_enable => mie_we,
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	u_mstatus_mpie_ff : entity work.flip_flop
		port map (
			i_d      => mpie_nxt,
			o_d      => mstatus_mpie,
			i_enable => mpie_we,
			i_clk    => i_clk,
			i_rst    => i_rst
		);

	u_mtvec_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => mtvec_we,
			i_d      => mtvec_nxt,
			o_d      => mtvec_reg
		);

	u_mscratch_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => mscratch_we,
			i_d      => new_value,
			o_d      => mscratch_reg
		);

	u_mepc_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => mepc_we,
			i_d      => mepc_nxt,
			o_d      => mepc_reg
		);

	u_mcause_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => mcause_we,
			i_d      => mcause_nxt,
			o_d      => mcause_reg
		);

	u_mtval_reg : entity work.generic_register
		generic map (
			data_width => 32
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => mtval_we,
			i_d      => mtval_nxt,
			o_d      => mtval_reg
		);

end architecture rtl;
