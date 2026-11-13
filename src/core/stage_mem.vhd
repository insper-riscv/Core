-- =============================================================================
-- Estágio MEM (Memory Access) do Pipeline RV32
--
-- Decodifica o endereço efetivo calculado no estágio EX (i_alu_out) usando as
-- constantes centralizadas em mem_map_consts e roteia os sinais de leitura,
-- escrita e máscara de bytes para os três caminhos de memória de dados.
-- Antes de rotear, confere o endereço efetivo original (i_ea) do load ou store:
-- um acesso desalinhado que o hardware não executa, ou um store à BOOT_MEMORY ou
-- à FLASH, gera a exceção de endereço (o_trap_take) já neste estágio, e nenhum
-- acesso à memória é emitido:
--   1. Segunda porta da memória FLASH (BOOT_MEMORY, e FLASH fora do barramento):
--      leitura de constantes e inicialização da seção .data no boot.
--   2. Memória RAM direta (RAM fora do barramento): leitura e escrita síncrona
--      de 1 ciclo de latência.
--   3. Porta externa (a FLASH e a RAM no barramento, e todo endereço fora das
--      três regiões): leitura e escrita com handshake de latência variável
--      (i_ext_ready / o_ext_wait).
-- Quando a porta externa conclui o acesso com i_ext_error em '1' (endereço que
-- nenhum escravo atende), o estágio gera a falha de acesso de load (causa 5) ou
-- de store (causa 7), com o endereço efetivo em o_trap_tval, pelo mesmo caminho
-- da exceção de endereço; o acesso com erro não tem efeito no processador.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;
use work.mem_map_consts.all;
use work.opcode_consts.all;
use work.trap_consts.all;

entity stage_mem is
    generic (
        -- Confere o endereço efetivo do load ou store (exceção em MEM); '0' deixa essa conferência para o estágio EX.
        check_ea         : boolean := true;
        -- A classificação do endereço efetivo (FLASH, SDRAM, memória principal, mesma região) vem registrada do EX/MEM
        -- pelas portas i_flag_*, em vez de ser decodificada do endereço neste estágio.
        flags_registered : boolean := false
    );
    port (
        -- Bit de validade da instrução no estágio MEM.
        i_valid       : in    std_logic;
        -- Endereço apresentado às memórias neste ciclo (o efetivo, ou o da segunda palavra de um acesso que cruza).
        i_alu_out     : in    word_t;
        -- Endereço efetivo original do load ou store, vindo do registrador EX/MEM.
        i_ea          : in    word_t;
        -- O endereço efetivo é atendido pela porta direta de dados da BOOT_MEMORY e da FLASH (com flags_registered).
        i_flag_flash  : in    std_logic := '0';
        -- O endereço efetivo sai pela porta externa, o barramento (com flags_registered).
        i_flag_sdram  : in    std_logic := '0';
        -- O endereço efetivo está na memória principal (com flags_registered).
        i_flag_main   : in    std_logic := '0';
        -- As duas palavras de um acesso que cruza ficam na mesma região (com flags_registered).
        i_flag_same   : in    std_logic := '0';
        -- O endereço efetivo aceita escrita no mapa do núcleo (com HAS_ACCESS_FAULTS).
        i_flag_ok_wr  : in    std_logic := '1';
        -- Campo funct3 do load ou store, vindo do registrador EX/MEM.
        i_funct3      : in    funct3_t;
        -- Dado alinhado para escrita em memória vindo do registrador EX/MEM.
        i_store_data  : in    word_t;
        -- Máscara de habilitação de bytes vinda do registrador EX/MEM.
        i_byte_mask   : in    byte_mask_t;
        -- Habilitação de escrita na memória vinda do registrador EX/MEM.
        i_we_ram      : in    std_logic;
        -- Habilitação de leitura na memória vinda do registrador EX/MEM.
        i_re_ram      : in    std_logic;
        -- Habilitação geral de acesso à memória vinda do registrador EX/MEM.
        i_en_ram      : in    std_logic;
        -- Sinaliza que o escravo externo concluiu a transação atual.
        i_ext_ready   : in    std_logic;
        -- A porta externa concluiu a transação atual com erro: nenhum escravo atende o endereço; só vale junto de
        -- i_ext_ready.
        i_ext_error   : in    std_logic := '0';
        -- Endereço de leitura enviado à segunda porta da memória FLASH.
        o_flash_addr2 : out   addr_t;
        -- Habilitação de leitura enviada à segunda porta da memória FLASH.
        o_flash_rden2 : out   std_logic;
        -- Endereço de acesso enviado à memória RAM interna.
        o_ram_addr    : out   addr_t;
        -- Dado de escrita enviado à memória RAM interna.
        o_ram_wdata   : out   word_t;
        -- Habilitação geral enviada à memória RAM interna.
        o_ram_en      : out   std_logic;
        -- Habilitação de escrita enviada à memória RAM interna.
        o_ram_wren    : out   std_logic;
        -- Habilitação de leitura enviada à memória RAM interna.
        o_ram_rden    : out   std_logic;
        -- Máscara de bytes enviada à memória RAM interna.
        o_ram_byteena : out   byte_mask_t;
        -- Endereço de acesso enviado à porta externa.
        o_ext_addr    : out   addr_t;
        -- Dado de escrita enviado à porta externa.
        o_ext_wdata   : out   word_t;
        -- Máscara de bytes enviada à porta externa.
        o_ext_byteena : out   byte_mask_t;
        -- Habilitação de leitura enviada à porta externa.
        o_ext_rden    : out   std_logic;
        -- Habilitação de escrita enviada à porta externa.
        o_ext_wren    : out   std_logic;
        -- Indica que o estágio MEM aguarda conclusão de acesso na porta externa.
        o_ext_wait    : out   std_logic;
        -- Exceção do load ou store em MEM, de endereço ou de falha de acesso ('1' = tomar o trap neste ciclo).
        o_trap_take   : out   std_logic;
        -- Código mcause da exceção (4 e 6 desalinhado de load e store, 5 e 7 falha de acesso de load e store).
        o_trap_cause  : out   word_t;
        -- Valor de mtval da exceção (o endereço efetivo).
        o_trap_tval   : out   word_t
    );
end entity stage_mem;

architecture rtl of stage_mem is

    -- Indica que o endereço acessado é atendido pela porta direta da BOOT_MEMORY e da FLASH.
    signal is_flash_data   : std_logic;
    -- Indica que o endereço acessado sai pela porta externa (barramento).
    signal is_sdram        : std_logic;
    -- Indica que o endereço acessado pertence à memória RAM direta.
    signal is_ram_internal : std_logic;
    -- Indica transação válida endereçada à porta externa.
    signal sdram_access    : std_logic;
    -- Opcode do acesso em MEM (LOAD, STORE ou zero), reconstruído dos sinais de leitura e escrita.
    signal mem_opcode      : opcode_t;
    -- Exceção de endereço do acesso em MEM, antes de qualquer acesso à memória.
    signal trap_take_int   : std_logic;
    -- Causa da exceção de endereço do acesso em MEM.
    signal trap_cause_int  : word_t;
    -- Valor de mtval da exceção de endereço do acesso em MEM.
    signal trap_tval_int   : word_t;
    -- A porta externa concluiu o acesso em MEM com erro: falha de acesso de load ou de store.
    signal ext_fault       : std_logic;
    -- Validade do acesso em MEM descontada a exceção: só o acesso que não gera trap chega às memórias.
    signal access_valid    : std_logic;

begin

    mem_opcode <= OPCODE_LOAD when i_re_ram = '1' else
                  OPCODE_STORE when i_we_ram = '1' else
                  (others => '0');

    u_ea_trap : entity work.trap_unit
        generic map (
            check_ea          => check_ea,
            ea_flags_external => flags_registered
        )
        port map (
            i_ea_main        => i_flag_main,
            i_ea_same_region => i_flag_same,
            i_ea_wr_ok       => i_flag_ok_wr,
            i_ex_valid       => i_valid,
            i_run            => '1',
            i_opcode         => mem_opcode,
            i_funct3         => i_funct3,
            i_rd_idx         => REG_ZERO,
            i_rs1_idx        => REG_ZERO,
            i_imm12          => (others => '0'),
            i_ea             => i_ea,
            i_cf_taken       => '0',
            i_cf_target      => (others => '0'),
            i_csr_illegal    => '0',
            i_illegal        => '0',
            o_take           => trap_take_int,
            o_mret_take      => open,
            o_cause          => trap_cause_int,
            o_tval           => trap_tval_int
        );

    access_valid <= i_valid and (not trap_take_int);

    -- A resposta de erro da porta externa conclui o acesso que foi emitido neste ciclo e gera a falha de acesso de
    -- load (causa 5) ou de store (causa 7), com o endereço efetivo em mtval. O erro só vale junto do ready, e só
    -- existe com falhas de acesso e com a checagem de endereço neste estágio (CSRs); o acesso emitido já passou da
    -- exceção de endereço (access_valid), então as duas não se somam.
    ext_fault <= sdram_access and i_ext_ready and i_ext_error
                 when (HAS_ACCESS_FAULTS and check_ea) else '0';

    o_trap_take  <= trap_take_int or ext_fault;
    o_trap_cause <= CAUSE_STORE_FAULT when (ext_fault = '1' and mem_opcode = OPCODE_STORE) else
                    CAUSE_LOAD_FAULT when ext_fault = '1' else
                    trap_cause_int;
    o_trap_tval  <= i_ea when ext_fault = '1' else trap_tval_int;

    -- A região sai da comparação do endereço com os limites constantes do mapa.
    is_flash_data   <= i_flag_flash when flags_registered else
                       '1' when is_direct_rom_addr(unsigned(i_alu_out)) else
                       '0';
    is_sdram        <= i_flag_sdram when flags_registered else
                       '1' when is_external_addr(unsigned(i_alu_out)) else
                       '0';
    is_ram_internal <= (not is_flash_data) and (not is_sdram);

    o_flash_addr2 <= i_alu_out(addr_t'range);
    o_flash_rden2 <= i_re_ram and access_valid and is_flash_data;

    o_ram_addr    <= i_alu_out(addr_t'range);
    o_ram_wdata   <= i_store_data;
    o_ram_en      <= i_en_ram and access_valid and is_ram_internal;
    o_ram_wren    <= i_we_ram and access_valid and is_ram_internal;
    o_ram_rden    <= i_re_ram and access_valid and is_ram_internal;
    o_ram_byteena <= i_byte_mask;

    sdram_access  <= access_valid and i_en_ram and is_sdram;
    o_ext_wait    <= sdram_access and (not i_ext_ready);
    o_ext_addr    <= i_alu_out(addr_t'range);
    o_ext_wdata   <= i_store_data;
    o_ext_byteena <= i_byte_mask;
    o_ext_wren    <= i_we_ram and sdram_access;
    o_ext_rden    <= i_re_ram and sdram_access;

end architecture rtl;
