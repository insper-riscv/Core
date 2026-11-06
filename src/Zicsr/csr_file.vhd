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
--   - O misa anuncia RV32I (RV32E quando base_e = true) e, quando has_m = true, a
--     extensão M.
--   - Com has_interrupts = true, mip e mie funcionam: mip (0x344) é somente leitura e
--     espelha as portas i_irq_software (bit 3, MSIP), i_irq_timer (bit 7, MTIP) e
--     i_irq_external (bit 11, MEIP), e mie (0x304) guarda os bits 3, 7 e 11 (MSIE, MTIE e
--     MEIE); os demais bits dos dois leem zero e ignoram a escrita, e a escrita em mip não
--     gera exceção. o_irq_pending vale '1' quando algum bit de mip e o de mie estão
--     ambos em '1', sem considerar mstatus.MIE. Sem has_interrupts as portas são
--     ignoradas e mie e mip leem zero e ignoram a escrita.
--   - A condição de tomada de interrupção é o_irq_take = mstatus.MIE e o_irq_pending. Com
--     mais de uma pendente, o_irq_cause escolhe a de maior prioridade: externa (causa 11),
--     software (causa 3) e timer (causa 7), no formato de mcause (bit 31 em '1').
--   - mtvec (0x305) tem BASE nos bits 31 a 2 e MODE no bit 0: '0' é o modo direto e '1' o
--     vetorado, que só existe com has_interrupts (sem ele o bit 0 lê zero). O bit 1 lê
--     zero (os modos 2 e 3 são reservados). No modo vetorado a BASE tem alinhamento de 64
--     bytes (os bits 5 a 2 leem zero), para que BASE + 4 x causa seja um OR de bits.
--     o_mtvec entrega a BASE (bits 1 e 0 em zero) e o_mtvec_vectored o MODE.
--   - Com has_zicntr = true, os contadores mcycle, minstret e time de 64 bits
--     (metades baixa e alta) respondem em 0xB00 a 0xB82 e 0xC00 a 0xC82. mcycle
--     soma 1 a cada ciclo, minstret soma 1 a cada pulso de i_retire e time soma 1
--     a cada tick_cycles ciclos. mcycle e minstret aceitam escrita; cycle, time e
--     instret (0xC00 a 0xC82) são somente leitura. Sem has_zicntr esses endereços
--     são inexistentes.
--   - Com has_zihpm = true, a extensão Zihpm define os 29 contadores de eventos de
--     índice 3 a 31: mhpmcounterK em 0xB00 + K, a metade alta em 0xB80 + K, os
--     espelhos somente leitura em 0xC00 + K e 0xC80 + K e o seletor de evento
--     mhpmeventK em 0x320 + K (4 bits; o código escolhe um bit de i_events, e o
--     código 0 não conta). Os 29 endereços existem sempre; os hpm_counters primeiros
--     (índices 3 a 2 + hpm_counters) têm contador de hpm_width bits, que soma 1 a cada
--     ciclo em que o evento escolhido vale '1' em i_events, e os demais leem zero e
--     ignoram a escrita, sem exceção. Os endereços do banco são decodificados pelos
--     7 bits altos (a faixa) e pelos 5 bits baixos (o índice). Sem has_zihpm esses
--     endereços são inexistentes.
--   - O registrador mcountinhibit (0x320) existe com has_zicntr ou has_zihpm: o bit 0
--     inibe mcycle, o bit 2 inibe minstret e os bits de 3 a 2 + hpm_counters inibem os
--     contadores de eventos; os demais bits leem zero e ignoram a escrita (o time não
--     é inibível). Um contador inibido mantém o valor e continua legível e gravável.
--
-- Todos os registradores de estado utilizam instâncias estruturais de
-- generic_register e flip_flop.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.csr_addr_consts.all;
use work.csr_event_consts.all;
use work.csr_value_consts.all;
use work.irq_consts.all;
use work.byte_mask_consts.all;
use work.word_consts.all;

entity csr_file is
	generic (
		-- Faz o misa anunciar a extensão M (bit 12), para o perfil que a inclui.
		has_m : boolean := true;
		-- Faz o misa anunciar a base E (bit 4) no lugar da I (bit 8), para o perfil de 16 registradores.
		base_e : boolean := false;
		-- Habilita os contadores da extensão Zicntr (mcycle, minstret, time e seus espelhos).
		has_zicntr : boolean := false;
		-- Ciclos de clock do core por tick do contador time (50 dá 1 MHz a 50 MHz).
		tick_cycles : positive := 50;
		-- Habilita a extensão Zihpm: os 29 endereços de contador, evento e espelho de índices 3 a 31 e os bits de mcountinhibit.
		has_zihpm : boolean := false;
		-- Quantidade de contadores de eventos reais da extensão Zihpm, de índices 3 a 2 + hpm_counters; os outros leem zero.
		hpm_counters : natural range 0 to HPM_MAX_COUNTERS := HPM_MAX_COUNTERS;
		-- Largura em bits de cada contador de eventos real (0 a 64).
		hpm_width : natural range 0 to 64 := 64;
		-- Habilita as interrupções de máquina: mip espelha as portas i_irq_* e mie guarda as máscaras.
		has_interrupts : boolean := false;
		-- A leitura do banco do Zihpm sai de um registrador: o_bank_read avisa que o endereço é do banco e que o valor lido só vale um ciclo depois de o endereço aparecer.
		hpm_registered_read : boolean := false
	);
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
		-- O endereço é do banco do Zihpm e a leitura registrada (hpm_registered_read) vale um ciclo depois.
		o_bank_read  : out std_logic;
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
		-- Pulso de um ciclo: uma instrução foi retirada em EX (incrementa minstret no ciclo seguinte).
		i_retire     : in  std_logic := '0';
		-- Cancela a retirada do ciclo anterior: a instrução gerou exceção no estágio MEM e não conta em minstret.
		i_retire_cancel : in std_logic := '0';
		-- Vetor de eventos: o bit K vale '1' nos ciclos em que o evento de código K ocorre (o bit 0 é ignorado).
		i_events     : in  std_logic_vector(EVENT_VECTOR_WIDTH - 1 downto 0) := (others => '0');
		-- Endereço base do tratador de traps armazenado no registrador mtvec.
		o_mtvec      : out word_t;
		-- Endereço de retorno de exceção armazenado no registrador mepc.
		o_mepc       : out word_t;
		-- Interrupção de software de máquina (MSIP), de nível, no domínio de clock do core.
		i_irq_software : in  std_logic := '0';
		-- Interrupção de timer de máquina (MTIP), de nível, no domínio de clock do core.
		i_irq_timer    : in  std_logic := '0';
		-- Interrupção externa de máquina (MEIP), de nível, no domínio de clock do core.
		i_irq_external : in  std_logic := '0';
		-- Há interrupção pendente e habilitada em mie, sem considerar mstatus.MIE ('0' sem has_interrupts).
		o_irq_pending  : out std_logic;
		-- Há interrupção a tomar: pendente, habilitada em mie e com mstatus.MIE em '1' ('0' sem has_interrupts).
		o_irq_take     : out std_logic;
		-- Código de mcause da interrupção de maior prioridade pendente (externa, software e timer).
		o_irq_cause    : out word_t;
		-- Modo de mtvec: '1' é o vetorado (interrupção vai a BASE + 4 x causa), '0' o direto.
		o_mtvec_vectored : out std_logic
	);
end entity csr_file;

architecture rtl of csr_file is

	-- Converte um booleano em std_logic ('1' para verdadeiro).
	function bool_to_sl(b : boolean) return std_logic is
	begin
		if b then
			return '1';
		end if;
		return '0';
	end function;

	-- Bit MIE (bit 3) armazenado no registrador mstatus.
	signal mstatus_mie       : std_logic;
	-- Bit MPIE (bit 7) armazenado no registrador mstatus.
	signal mstatus_mpie      : std_logic;
	-- Valor registrado de BASE no CSR mtvec (bits 31 a 2; os dois bits baixos são sempre zero).
	signal mtvec_reg         : word_t;
	-- Modo registrado de mtvec ('1' é o vetorado; sempre '0' sem has_interrupts).
	signal mtvec_mode        : std_logic;
	-- Palavra de mtvec como o programa a lê: BASE e o modo no bit 0.
	signal mtvec_value       : word_t;
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
	-- Valor lido do misa, conforme as extensões do perfil.
	signal misa_value        : word_t;
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

	-- Indica que i_addr é um endereço de contador da extensão Zicntr e o perfil a inclui.
	signal is_cntr_addr      : std_logic;
	-- Valor lido do contador selecionado por i_addr (zero fora dos endereços de contador).
	signal cntr_value        : word_t;
	-- Metade baixa de mcycle.
	signal mcycle_lo         : word_t;
	-- Metade alta de mcycle.
	signal mcycle_hi         : word_t;
	-- Metade baixa de minstret.
	signal minstret_lo       : word_t;
	-- Metade alta de minstret.
	signal minstret_hi       : word_t;
	-- Metade baixa de time.
	signal time_lo           : word_t;
	-- Metade alta de time.
	signal time_hi           : word_t;
	-- Pulso de tick do contador time.
	signal time_tick         : std_logic;
	-- Retirada do ciclo anterior ainda não somada em minstret (soma no ciclo seguinte, salvo cancelamento).
	signal retire_pending    : std_logic;
	-- Soma em minstret neste ciclo: a retirada pendente, se um trap de MEM não a cancelou.
	signal minstret_inc      : std_logic;
	-- Metade baixa de minstret como o programa a lê: o contador mais a retirada pendente.
	signal minstret_rd_lo    : word_t;
	-- Metade alta de minstret como o programa a lê: o contador mais o vai-um da retirada pendente.
	signal minstret_rd_hi    : word_t;
	-- Escrita efetiva de uma instrução CSR no endereço do contador (sem trap nem mret no ciclo).
	signal cntr_write        : std_logic;
	-- Escrita na metade baixa de mcycle.
	signal mcycle_we_lo      : std_logic;
	-- Escrita na metade alta de mcycle.
	signal mcycle_we_hi      : std_logic;
	-- Escrita na metade baixa de minstret.
	signal minstret_we_lo    : std_logic;
	-- Escrita na metade alta de minstret.
	signal minstret_we_hi    : std_logic;

	-- O perfil tem o registrador mcountinhibit (Zicntr ou Zihpm).
	constant HAS_INHIBIT     : boolean := has_zicntr or has_zihpm;
	-- Bits de mcountinhibit de mcycle (0) e minstret (2) que aceitam escrita, quando há Zicntr.
	function inhibit_mask return std_logic_vector is
	begin
		if has_zicntr then
			return "101";
		end if;
		return "000";
	end function;

	-- Valor registrado dos bits 2 a 0 de mcountinhibit (só os bits do mask podem valer '1').
	signal inhibit_reg       : std_logic_vector(2 downto 0);
	-- Habilitação de escrita nos bits 2 a 0 de mcountinhibit.
	signal inhibit_we        : std_logic;
	-- Soma de mcycle neste ciclo: sempre, salvo inibição.
	signal mcycle_inc        : std_logic;
	-- Próximo valor dos bits 2 a 0 de mcountinhibit: o escrito, só nos bits que aceitam escrita.
	signal inhibit_nxt       : std_logic_vector(2 downto 0);
	-- Faixa do endereço (bits [11:5]).
	signal addr_range        : std_logic_vector(6 downto 0);
	-- Índice do endereço dentro da faixa (bits [4:0]).
	signal addr_idx          : std_logic_vector(4 downto 0);
	-- O índice é de um contador de eventos (3 a 31).
	signal idx_is_hpm        : std_logic;
	-- O endereço está na faixa de mcountinhibit e dos seletores de evento.
	signal in_event_range    : std_logic;
	-- O endereço está numa faixa de metades baixas (de máquina ou espelho).
	signal in_lo_range       : std_logic;
	-- O endereço está numa faixa de metades altas (de máquina ou espelho).
	signal in_hi_range       : std_logic;
	-- O endereço é o de mcountinhibit (faixa dos seletores de evento, índice 0).
	signal is_inhibit_addr   : std_logic;
	-- Indica que i_addr é um endereço da extensão Zihpm ou de mcountinhibit e o perfil o inclui.
	signal is_ext_addr       : std_logic;
	-- Valor lido do CSR da extensão Zihpm ou de mcountinhibit selecionado por i_addr (zero nos outros).
	signal ext_value         : word_t;
	-- Valor lido pelo banco de contadores de eventos (zero fora dele).
	signal bank_rdata        : word_t;
	-- Bits 2 a 0 de mcountinhibit como o programa os lê (zero fora do endereço).
	signal inhibit_word      : word_t;

	-- Valor das três portas de interrupção na ordem software, timer e externa (zero sem has_interrupts).
	signal irq_in            : std_logic_vector(IRQ_COUNT - 1 downto 0);
	-- Valor registrado das máscaras MSIE, MTIE e MEIE na mesma ordem.
	signal irq_en_reg        : std_logic_vector(IRQ_COUNT - 1 downto 0);
	-- Próximo valor das máscaras, tirado do valor escrito.
	signal irq_en_nxt        : std_logic_vector(IRQ_COUNT - 1 downto 0);
	-- Habilitação de escrita em mie.
	signal irq_en_we         : std_logic;
	-- Palavra de mip como o programa a lê.
	signal mip_value         : word_t;
	-- Palavra de mie como o programa a lê.
	signal mie_value         : word_t;

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
	-- Modo vetorado pedido pela escrita em mtvec (bit 0 do valor escrito, só com has_interrupts).
	signal mtvec_mode_nxt    : std_logic;
	-- Bits 5 a 2 de BASE como serão gravados: zero no modo vetorado (alinhamento de 64 bytes).
	signal mtvec_base_low    : std_logic_vector(3 downto 0);
	-- Interrupções pendentes e habilitadas em mie, na ordem software, timer e externa.
	signal irq_pend_vec      : std_logic_vector(IRQ_COUNT - 1 downto 0);
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
	misa_value    <= MISA_E_WITH_M when (base_e and has_m) else
	                 MISA_E_BASE   when base_e else
	                 MISA_WITH_M   when has_m else
	                 MISA_BASE;

	mstatus_value <= (12 => '1', 11 => '1', 7 => mstatus_mpie, 3 => mstatus_mie, others => '0');

	-- Seleção combinacional de leitura do CSR.
	with i_addr select
		old_value <=
			mstatus_value when ADDR_MSTATUS,
			misa_value    when ADDR_MISA,
			mtvec_value   when ADDR_MTVEC,
			mscratch_reg  when ADDR_MSCRATCH,
			mepc_reg      when ADDR_MEPC,
			mcause_reg    when ADDR_MCAUSE,
			mtval_reg     when ADDR_MTVAL,
			mie_value     when ADDR_MIE,
			mip_value     when ADDR_MIP,
			cntr_value or ext_value when others;

	with i_addr select
		is_known_addr <=
			'1' when ADDR_MSTATUS | ADDR_MISA | ADDR_MIE | ADDR_MTVEC | ADDR_MSTATUSH |
			         ADDR_MSCRATCH | ADDR_MEPC | ADDR_MCAUSE | ADDR_MTVAL | ADDR_MIP |
			         ADDR_MVENDORID | ADDR_MARCHID | ADDR_MIMPID | ADDR_MHARTID | ADDR_MCONFIGPTR,
			is_cntr_addr or is_ext_addr when others;

	o_rdata <= old_value;
	o_mtvec <= mtvec_reg(31 downto 2) & BYTE_OFFSET_0;
	o_mtvec_vectored <= mtvec_mode;
	o_mepc  <= mepc_reg;

	-- Cálculo do valor modificado conforme os bits [1:0] de i_op (escrita, set ou clear de bits).
	with i_op(1 downto 0) select
		new_value <=
			i_wdata                     when CSR_OP_WRITE,
			old_value or i_wdata        when CSR_OP_SET,
			old_value and (not i_wdata) when others;

	has_write_effect <= '1' when (i_op(1 downto 0) = CSR_OP_WRITE or i_src_zero = '0') else '0';
	is_read_only     <= '1' when i_addr(11 downto 10) = CSR_ADDR_READ_ONLY else '0';
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
	mtvec_mode_nxt <= new_value(0) when has_interrupts else '0';
	mtvec_base_low <= (others => '0') when mtvec_mode_nxt = '1' else new_value(5 downto 2);
	mtvec_nxt      <= new_value(31 downto 6) & mtvec_base_low & BYTE_OFFSET_0;
	mtvec_value    <= mtvec_reg(31 downto 2) & '0' & mtvec_mode;

	mscratch_we <= '1' when (csr_write_valid = '1' and i_addr = ADDR_MSCRATCH and i_trap_take = '0' and i_mret_take = '0') else '0';

	mepc_we     <= '1' when (i_trap_take = '1' or (csr_write_valid = '1' and i_addr = ADDR_MEPC and i_mret_take = '0')) else '0';
	mepc_nxt    <= i_trap_pc(31 downto 2) & BYTE_OFFSET_0 when i_trap_take = '1' else
	               new_value(31 downto 2) & BYTE_OFFSET_0;

	mcause_we   <= '1' when (i_trap_take = '1' or (csr_write_valid = '1' and i_addr = ADDR_MCAUSE and i_mret_take = '0')) else '0';
	mcause_nxt  <= i_trap_cause when i_trap_take = '1' else new_value;

	mtval_we    <= '1' when (i_trap_take = '1' or (csr_write_valid = '1' and i_addr = ADDR_MTVAL and i_mret_take = '0')) else '0';
	mtval_nxt   <= i_trap_tval  when i_trap_take = '1' else new_value;

	-- Interrupções de máquina: mip espelha as portas, mie guarda as máscaras.
	irq_in <= (i_irq_external & i_irq_timer & i_irq_software) when has_interrupts else (others => '0');

	mip_value <= (IRQ_BIT_EXTERNAL => irq_in(IRQ_IDX_EXTERNAL),
	              IRQ_BIT_TIMER    => irq_in(IRQ_IDX_TIMER),
	              IRQ_BIT_SOFTWARE => irq_in(IRQ_IDX_SOFTWARE),
	              others           => '0');
	mie_value <= (IRQ_BIT_EXTERNAL => irq_en_reg(IRQ_IDX_EXTERNAL),
	              IRQ_BIT_TIMER    => irq_en_reg(IRQ_IDX_TIMER),
	              IRQ_BIT_SOFTWARE => irq_en_reg(IRQ_IDX_SOFTWARE),
	              others           => '0');

	irq_en_nxt(IRQ_IDX_EXTERNAL) <= new_value(IRQ_BIT_EXTERNAL);
	irq_en_nxt(IRQ_IDX_TIMER)    <= new_value(IRQ_BIT_TIMER);
	irq_en_nxt(IRQ_IDX_SOFTWARE) <= new_value(IRQ_BIT_SOFTWARE);

	irq_pend_vec  <= irq_in and irq_en_reg;
	o_irq_pending <= '1' when irq_pend_vec /= (IRQ_COUNT - 1 downto 0 => '0') else '0';
	o_irq_take    <= mstatus_mie when irq_pend_vec /= (IRQ_COUNT - 1 downto 0 => '0') else '0';
	o_irq_cause   <= CAUSE_IRQ_EXTERNAL when irq_pend_vec(IRQ_IDX_EXTERNAL) = '1' else
	                 CAUSE_IRQ_SOFTWARE when irq_pend_vec(IRQ_IDX_SOFTWARE) = '1' else
	                 CAUSE_IRQ_TIMER;

	gen_irq : if has_interrupts generate
		irq_en_we <= '1' when (csr_write_valid = '1' and i_addr = ADDR_MIE and i_trap_take = '0' and i_mret_take = '0') else '0';

		u_irq_en_reg : entity work.generic_register
			generic map (
				data_width => IRQ_COUNT
			)
			port map (
				i_clk    => i_clk,
				i_rst    => i_rst,
				i_enable => irq_en_we,
				i_d      => irq_en_nxt,
				o_d      => irq_en_reg
			);
	end generate gen_irq;

	gen_no_irq : if not has_interrupts generate
		irq_en_we  <= '0';
		irq_en_reg <= (others => '0');
	end generate gen_no_irq;

	-- O modo de mtvec só existe com interrupções: sem elas MODE lê sempre zero.
	gen_mtvec_mode : if has_interrupts generate
		u_mtvec_mode_ff : entity work.flip_flop
			port map (
				i_d      => mtvec_mode_nxt,
				o_d      => mtvec_mode,
				i_enable => mtvec_we,
				i_clk    => i_clk,
				i_rst    => i_rst
			);
	end generate gen_mtvec_mode;

	gen_no_mtvec_mode : if not has_interrupts generate
		mtvec_mode <= '0';
	end generate gen_no_mtvec_mode;

	-- Contadores da extensão Zicntr.
	cntr_write <= '1' when (csr_write_valid = '1' and i_trap_take = '0' and i_mret_take = '0') else '0';

	mcycle_inc     <= not inhibit_reg(0);
	mcycle_we_lo   <= cntr_write and bool_to_sl(i_addr = ADDR_MCYCLE);
	mcycle_we_hi   <= cntr_write and bool_to_sl(i_addr = ADDR_MCYCLEH);
	minstret_we_lo <= cntr_write and bool_to_sl(i_addr = ADDR_MINSTRET);
	minstret_we_hi <= cntr_write and bool_to_sl(i_addr = ADDR_MINSTRETH);

	gen_zicntr : if has_zicntr generate

		is_cntr_addr <= '1' when (i_addr = ADDR_MCYCLE or i_addr = ADDR_MCYCLEH or
		                          i_addr = ADDR_MINSTRET or i_addr = ADDR_MINSTRETH or
		                          i_addr = ADDR_CYCLE or i_addr = ADDR_CYCLEH or
		                          i_addr = ADDR_TIME or i_addr = ADDR_TIMEH or
		                          i_addr = ADDR_INSTRET or i_addr = ADDR_INSTRETH) else '0';

		cntr_value <= mcycle_lo   when (i_addr = ADDR_MCYCLE or i_addr = ADDR_CYCLE) else
		              mcycle_hi   when (i_addr = ADDR_MCYCLEH or i_addr = ADDR_CYCLEH) else
		              minstret_rd_lo when (i_addr = ADDR_MINSTRET or i_addr = ADDR_INSTRET) else
		              minstret_rd_hi when (i_addr = ADDR_MINSTRETH or i_addr = ADDR_INSTRETH) else
		              time_lo     when i_addr = ADDR_TIME else
		              time_hi     when i_addr = ADDR_TIMEH else
		              (others => '0');

		-- mcycle soma 1 a cada ciclo de clock do core, inclusive nos ciclos de parada.
		u_mcycle : entity work.counter64
			port map (
				i_clk   => i_clk,
				i_rst   => i_rst,
				i_inc   => mcycle_inc,
				i_we_lo => mcycle_we_lo,
				i_we_hi => mcycle_we_hi,
				i_wdata => new_value,
				o_lo    => mcycle_lo,
				o_hi    => mcycle_hi
			);

		-- A retirada de EX fica pendente por um ciclo, para que um trap tomado em MEM a cancele; uma escrita em
		-- minstret no mesmo ciclo descarta a retirada da própria instrução de escrita.
		process (i_clk)
		begin
			if rising_edge(i_clk) then
				if i_rst = '1' then
					retire_pending <= '0';
				else
					retire_pending <= i_retire and (not (minstret_we_lo or minstret_we_hi));
				end if;
			end if;
		end process;

		minstret_inc <= retire_pending and (not i_retire_cancel) and (not inhibit_reg(2));

		-- O programa lê minstret já com a retirada pendente somada.
		minstret_rd_lo <= std_logic_vector(unsigned(minstret_lo) + unsigned'(0 => retire_pending and (not inhibit_reg(2))));
		minstret_rd_hi <= std_logic_vector(unsigned(minstret_hi) +
		                  unsigned'(0 => retire_pending and (not inhibit_reg(2)) and bool_to_sl(minstret_lo = WORD_ALL_ONES)));

		-- minstret soma 1 a cada instrução retirada em EX, um ciclo depois da retirada e salvo cancelamento.
		u_minstret : entity work.counter64
			port map (
				i_clk   => i_clk,
				i_rst   => i_rst,
				i_inc   => minstret_inc,
				i_we_lo => minstret_we_lo,
				i_we_hi => minstret_we_hi,
				i_wdata => new_value,
				o_lo    => minstret_lo,
				o_hi    => minstret_hi
			);

		-- Divisor que gera o tick do contador time.
		u_time_tick : entity work.tick_divider
			generic map (
				tick_cycles => tick_cycles
			)
			port map (
				i_clk  => i_clk,
				i_rst  => i_rst,
				o_tick => time_tick
			);

		-- time soma 1 a cada tick e não aceita escrita (os endereços 0xC01 e 0xC81 são somente leitura).
		u_time : entity work.counter64
			port map (
				i_clk   => i_clk,
				i_rst   => i_rst,
				i_inc   => time_tick,
				i_we_lo => '0',
				i_we_hi => '0',
				i_wdata => (others => '0'),
				o_lo    => time_lo,
				o_hi    => time_hi
			);

	end generate gen_zicntr;

	gen_no_zicntr : if not has_zicntr generate
		is_cntr_addr <= '0';
		cntr_value   <= (others => '0');
		mcycle_lo    <= (others => '0');
		mcycle_hi    <= (others => '0');
		minstret_lo  <= (others => '0');
		minstret_hi  <= (others => '0');
		time_lo      <= (others => '0');
		time_hi      <= (others => '0');
		time_tick    <= '0';
	end generate gen_no_zicntr;

	-- Decodificação dos endereços de mcountinhibit e do Zihpm: a faixa pelos bits altos, o índice pelos 5 bits baixos.
	addr_range       <= i_addr(11 downto 5);
	addr_idx         <= i_addr(4 downto 0);
	idx_is_hpm       <= '1' when unsigned(addr_idx) >= HPM_FIRST_INDEX else '0';
	in_event_range   <= '1' when addr_range = RANGE_MHPMEVENT else '0';
	in_lo_range      <= '1' when (addr_range = RANGE_MHPMCOUNTER or addr_range = RANGE_HPMCOUNTER) else '0';
	in_hi_range      <= '1' when (addr_range = RANGE_MHPMCOUNTERH or addr_range = RANGE_HPMCOUNTERH) else '0';
	is_inhibit_addr  <= in_event_range and bool_to_sl(unsigned(addr_idx) = 0);

	-- Bits de mcountinhibit de mcycle e minstret.
	gen_inhibit : if has_zicntr generate
		inhibit_we  <= cntr_write and is_inhibit_addr;
		inhibit_nxt <= new_value(2 downto 0) and inhibit_mask;

		u_inhibit_reg : entity work.generic_register
			generic map (
				data_width => inhibit_reg'length
			)
			port map (
				i_clk    => i_clk,
				i_rst    => i_rst,
				i_enable => inhibit_we,
				i_d      => inhibit_nxt,
				o_d      => inhibit_reg
			);
	end generate gen_inhibit;

	gen_no_inhibit : if not has_zicntr generate
		inhibit_we  <= '0';
		inhibit_nxt <= (others => '0');
		inhibit_reg <= (others => '0');
	end generate gen_no_inhibit;

	-- Banco de contadores de eventos da extensão Zihpm.
	gen_zihpm : if has_zihpm generate
		u_hpm_bank : entity work.hpm_counter_bank
			generic map (
				hpm_counters => hpm_counters,
				hpm_width    => hpm_width,
				registered_read => hpm_registered_read
			)
			port map (
				i_clk         => i_clk,
				i_rst         => i_rst,
				i_events      => i_events,
				i_idx         => addr_idx,
				i_sel_inhibit => is_inhibit_addr,
				i_sel_event   => in_event_range,
				i_sel_lo      => in_lo_range,
				i_sel_hi      => in_hi_range,
				i_we          => cntr_write,
				i_wdata       => new_value,
				o_rdata       => bank_rdata
			);

		is_ext_addr <= is_inhibit_addr or
		               (idx_is_hpm and (in_event_range or in_lo_range or in_hi_range));
		o_bank_read <= is_ext_addr when hpm_registered_read else '0';
	end generate gen_zihpm;

	gen_no_zihpm : if not has_zihpm generate
		bank_rdata  <= (others => '0');
		o_bank_read <= '0';
		is_ext_addr <= is_inhibit_addr and bool_to_sl(has_zicntr);
	end generate gen_no_zihpm;

	-- Leitura de mcountinhibit: os bits 2 a 0 daqui e os de 3 em diante do banco.
	inhibit_word(2 downto 0)  <= inhibit_reg and (2 downto 0 => is_inhibit_addr);
	inhibit_word(31 downto 3) <= (others => '0');
	ext_value <= bank_rdata or inhibit_word;

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
			data_width => word_t'length
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
			data_width => word_t'length
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
			data_width => word_t'length
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
			data_width => word_t'length
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
			data_width => word_t'length
		)
		port map (
			i_clk    => i_clk,
			i_rst    => i_rst,
			i_enable => mtval_we,
			i_d      => mtval_nxt,
			o_d      => mtval_reg
		);

end architecture rtl;
