-- =============================================================================
-- Registrador de estágio EX/MEM do pipeline RV32IM de 5 estágios
--
-- Captura, na borda de subida de i_clk, o resultado calculado no estágio EX
-- (ULA, MulDiv ou CSR), o dado e a máscara de bytes preparados pelo
-- StoreManager, o endereço do registrador destino rd e os sinais de controle
-- de memória e write-back, disponibilizando-os ao estágio MEM.
--
-- Prioridade dos controles síncronos:
--   1. i_rst = '1' ou i_flush = '1' -> zera os controles e marca o pacote como
--                                      bolha (o_valid = '0'); o PC, o resultado,
--                                      o dado e a máscara de escrita e o funct3
--                                      não são limpos.
--   2. i_en = '1'                   -> captura as entradas normalmente.
--   3. i_en = '0'                   -> mantém o estado atual (stall).
--
-- Só os bits de controle têm limpeza síncrona, de modo que o flush de exceção não
-- alimenta os campos de dados. O valor de uma bolha nunca produz efeito, porque
-- o estágio MEM e o adiantamento só o usam sob o_valid, os habilitadores de
-- memória e o_we_ok, todos zerados.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;
use work.mem_map_consts.all;
use work.byte_mask_consts.all;
use work.ext_ram_consts.all;
use work.funct3_consts.all;

entity reg_ex_mem is
    port (
        -- Sinal de clock.
        i_clk         : in    std_logic;
        -- Sinal de reset síncrono ativo em '1'.
        i_rst         : in    std_logic;
        -- Habilita a atualização do registrador EX/MEM ('1' = avança, '0' = congela).
        i_en          : in    std_logic;
        -- Limpa o registrador injetando bolha ('1' = flush por exceção ou espera de FENCE.I).
        i_flush       : in    std_logic;
        -- Validade da instrução vinda do estágio EX.
        i_valid       : in    std_logic;
        -- PC da instrução vinda do estágio EX (vira o mepc se o acesso à memória gerar exceção).
        i_pc          : in    word_t;
        -- Campo funct3 da instrução vinda do estágio EX (tamanho e sinal do acesso à memória).
        i_funct3      : in    funct3_t;
        -- Resultado final do estágio EX (endereço de memória ou resultado de operação).
        i_alu_out     : in    word_t;
        -- Resultado da ULA em EX, o endereço efetivo de um load ou store, de onde sai a classificação registrada do
        -- endereço.
        i_ea          : in    word_t := (others => '0');
        -- Dado alinhado para escrita em memória vindo do StoreManager.
        i_store_data  : in    word_t;
        -- Máscara de habilitação de bytes para escrita na RAM vinda do StoreManager.
        i_byte_mask   : in    byte_mask_t;
        -- Endereço do registrador destino rd.
        i_rd          : in    reg_t;
        -- Habilita escrita no banco de registradores no estágio WB.
        i_we_reg      : in    std_logic;
        -- Habilita escrita na memória de dados no estágio MEM.
        i_we_ram      : in    std_logic;
        -- Habilita leitura da memória de dados no estágio MEM.
        i_re_ram      : in    std_logic;
        -- Habilita acesso à memória de dados no estágio MEM.
        i_en_ram      : in    std_logic;
        -- Modo de extensão de leitura da memória de dados.
        i_ext_ram_op  : in    ext_ram_op_t;
        -- Seletor da fonte de escrita no estágio WB.
        i_wb_sel      : in    wb_sel_t;
        -- Validade da instrução registrada no estágio MEM.
        o_valid       : out   std_logic;
        -- Resultado do estágio EX registrado para o estágio MEM (e adiantamento EX/MEM).
        o_alu_out     : out   word_t;
        -- Dado de escrita alinhado registrado para o estágio MEM.
        o_store_data  : out   word_t;
        -- Máscara de bytes registrada para o estágio MEM.
        o_byte_mask   : out   byte_mask_t;
        -- Endereço de rd registrado para o estágio MEM (e Forwarding Unit).
        o_rd          : out   reg_t;
        -- Habilitação de escrita em registrador registrada para o estágio MEM.
        o_we_reg      : out   std_logic;
        -- A instrução é válida e escreve em registrador (registrada, para a seleção do adiantamento).
        o_we_ok       : out   std_logic;
        -- Habilitação de escrita na RAM registrada para o estágio MEM.
        o_we_ram      : out   std_logic;
        -- Habilitação de leitura da RAM registrada para o estágio MEM.
        o_re_ram      : out   std_logic;
        -- A instrução em MEM é um load com rd diferente de x0 (para a detecção load-use em ID).
        o_ld          : out   std_logic;
        -- Habilitação de acesso à RAM registrada para o estágio MEM.
        o_en_ram      : out   std_logic;
        -- Modo de extensão de leitura da RAM registrado para o estágio MEM.
        o_ext_ram_op  : out   ext_ram_op_t;
        -- Seletor de write-back registrado para o estágio MEM.
        o_wb_sel      : out   wb_sel_t;
        -- PC da instrução registrado para o estágio MEM.
        o_pc          : out   word_t;
        -- Campo funct3 registrado para o estágio MEM.
        o_funct3      : out   funct3_t;
        -- O endereço registrado é atendido pela porta direta de dados da BOOT_MEMORY e da FLASH (decodificado em EX,
        -- registrado aqui).
        o_is_flash    : out   std_logic;
        -- O endereço registrado sai pela porta externa (barramento): a FLASH ou a RAM no barramento e tudo fora das três
        -- regiões.
        o_is_sdram    : out   std_logic;
        -- O endereço registrado cai numa memória do barramento com ready próprio (a FLASH ou a RAM no barramento), a mesma
        -- classificação que o interconector faria sobre o endereço; decidida em EX, registrada aqui.
        o_is_bus_mem  : out   std_logic;
        -- O endereço registrado está na memória principal.
        o_in_main     : out   std_logic;
        -- As duas palavras de um acesso que cruza o endereço registrado ficam na mesma região da memória principal.
        o_same_region : out   std_logic;
        -- O endereço registrado aceita escrita no mapa do núcleo (sempre '1' sem HAS_ACCESS_FAULTS); a BOOT_MEMORY e a
        -- FLASH são só de leitura.
        o_ok_wr       : out   std_logic;
        -- O load ou o store registrado cruza a palavra (decidido em EX, registrado aqui; sempre '0' sem HAS_ZICCLSM).
        o_cross       : out   std_logic;
        -- O load ou store registrado é exceção de endereço quando está na última palavra da região da memória principal
        -- (cruza a palavra com Zicclsm, ou desalinhado sem ele); decidido em EX, sempre '0' sem HAS_ZICSR.
        o_ea_xlast    : out   std_logic;
        -- O load ou store registrado é desalinhado, e é exceção de endereço se estiver fora da memória principal;
        -- decidido em EX, sempre '0' sem HAS_ZICSR.
        o_ea_unal     : out   std_logic;
        -- O store registrado é exceção de endereço se a região não aceitar escrita; decidido em EX, sempre '0' sem
        -- HAS_ACCESS_FAULTS.
        o_ea_stf      : out   std_logic
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
    signal r_rd         : reg_t  := (others => '0');
    -- Habilitação de escrita em registrador armazenada.
    signal r_we_reg     : std_logic    := '0';
    -- Validade e escrita em registrador armazenadas juntas.
    signal r_we_ok      : std_logic    := '0';
    -- Habilitação de escrita na RAM armazenada.
    signal r_we_ram     : std_logic    := '0';
    -- Habilitação de leitura da RAM armazenada.
    signal r_re_ram     : std_logic    := '0';
    -- Load com rd diferente de x0 armazenado.
    signal r_ld         : std_logic    := '0';
    -- Entrada: o registrador destino é diferente de x0.
    signal in_rd_nz     : std_logic;
    -- Habilitação de acesso à RAM armazenada.
    signal r_en_ram     : std_logic    := '0';
    -- Modo de extensão da RAM armazenado.
    signal r_ext_ram_op : ext_ram_op_t := (others => '0');
    -- Seletor de write-back armazenado.
    signal r_wb_sel     : wb_sel_t     := (others => '0');
    -- O endereço registrado é atendido pela porta direta de dados da BOOT_MEMORY e da FLASH.
    signal r_is_flash   : std_logic    := '0';
    -- O endereço registrado sai pela porta externa (barramento).
    signal r_is_sdram   : std_logic    := '0';
    -- O endereço registrado cai numa memória do barramento com ready próprio.
    signal r_is_bus_mem : std_logic    := '0';
    -- O endereço registrado está na memória principal.
    signal r_in_main    : std_logic    := '0';
    -- O endereço está na última palavra de uma região (a seguinte é de outra).
    signal r_last       : std_logic    := '0';
    -- O endereço registrado aceita escrita no mapa.
    signal r_ok_wr      : std_logic    := '1';
    -- O acesso registrado cruza a palavra.
    signal r_cross      : std_logic    := '0';
    -- O acesso registrado é exceção de endereço se estiver na última palavra da região da memória principal.
    signal r_ea_xlast   : std_logic    := '0';
    -- O acesso registrado é desalinhado e é exceção de endereço se estiver fora da memória principal.
    signal r_ea_unal    : std_logic    := '0';
    -- O acesso registrado é store e é exceção de endereço se a região não aceitar escrita (com HAS_ACCESS_FAULTS).
    signal r_ea_stf     : std_logic    := '0';

    -- Entrada de r_is_flash, decodificada do resultado da ULA.
    signal in_is_flash : std_logic;
    -- Entrada de r_is_sdram, decodificada do resultado da ULA.
    signal in_is_sdram : std_logic;
    -- Entrada de r_is_bus_mem, decodificada do resultado da ULA.
    signal in_is_bus_mem : std_logic;
    -- Entrada de r_in_main, decodificada do resultado da ULA.
    signal in_in_main  : std_logic;
    -- Entrada de r_last, decodificada do resultado da ULA.
    signal in_last     : std_logic;
    -- Entrada de r_ok_wr, decodificada do resultado da ULA.
    signal in_ok_wr    : std_logic;
    -- Entrada de r_cross, decidida pelos controles do acesso e pelo byte do endereço efetivo.
    signal in_cross    : std_logic;
    -- Entrada de r_ea_xlast, decidida pelo funct3, pelos controles e pelos dois bits baixos do endereço efetivo.
    signal in_ea_xlast : std_logic;
    -- Entrada de r_ea_unal, decidida pelo funct3, pelos controles e pelos dois bits baixos do endereço efetivo.
    signal in_ea_unal  : std_logic;
    -- Entrada de r_ea_stf, decidida pelos controles e por HAS_ACCESS_FAULTS.
    signal in_ea_stf   : std_logic;
    -- O acesso é um load; quando os dois controles sobem, o load tem prioridade sobre o store.
    signal in_is_load  : std_logic;
    -- O acesso é um store.
    signal in_is_store : std_logic;
    -- O acesso é de meia palavra (LH, LHU ou SH).
    signal in_is_half  : std_logic;
    -- O acesso é de palavra (LW ou SW).
    signal in_is_word  : std_logic;
    -- O acesso é de meia palavra de store (SH).
    signal in_is_sh    : std_logic;
    -- O acesso é desalinhado, executado ou não pelo hardware.
    signal in_unaligned : std_logic;
    -- O acesso ocupa duas palavras.
    signal in_crossing : std_logic;

begin

    -- A classificação do endereço sai do estágio EX e fica registrada: o estágio MEM parte dela, sem decodificar o
    -- endereço.
    in_is_flash <= '1' when is_direct_rom_addr(unsigned(i_ea)) else '0';
    in_is_sdram <= '1' when is_external_addr(unsigned(i_ea)) else '0';
    in_is_bus_mem <= '1' when is_bus_mem_addr(unsigned(i_ea)) else '0';
    in_in_main  <= '1' when is_main_addr(unsigned(i_ea)) else '0';
    in_last     <= '1' when is_last_word(unsigned(i_ea)) else '0';

    -- A validade do endereço para escrita no mapa do núcleo sai de EX como a classificação, para o estágio MEM só
    -- conferir o bit. O endereço que nenhuma região atende não é recusado aqui: a porta externa responde erro.

    gen_faults : if HAS_ACCESS_FAULTS generate
        in_ok_wr <= '1' when addr_writable(unsigned(i_ea)) else '0';
    end generate gen_faults;

    gen_no_faults : if not HAS_ACCESS_FAULTS generate
        in_ok_wr <= '1';
    end generate gen_no_faults;

    -- O cruzamento da palavra também sai de EX e fica registrado: o estágio MEM só confere o bit.
    in_rd_nz <= '1' when i_rd /= REG_IDX_ZERO else '0';
    in_cross <= is_cross_access(i_re_ram, i_we_ram, i_ext_ram_op, i_byte_mask, i_ea(1 downto 0)) when HAS_ZICCLSM else '0';

    -- A exceção de endereço do acesso (as causas 4 e 6 do desalinhamento que o hardware não executa e a falha de store
    -- da causa 7 em região só de leitura) é decidida em MEM por três bits que saem de EX só do funct3, dos controles e
    -- dos dois bits baixos do endereço, que o somador da ULA entrega cedo, combinados com a região registrada. Na
    -- memória principal com Zicclsm o hardware executa o desalinhamento, e só o acesso que cruza a palavra e está na
    -- última palavra da região é exceção; sem Zicclsm todo desalinhado o é. Fora da memória principal, todo
    -- desalinhado é exceção. O store a região que não aceita escrita é exceção com HAS_ACCESS_FAULTS. O load tem
    -- prioridade sobre o store quando os dois controles sobem.
    in_is_load  <= i_re_ram;
    in_is_store <= i_we_ram and (not i_re_ram);
    in_is_half  <= '1' when (i_funct3 = FUNCT3_LH or i_funct3 = FUNCT3_LHU) else '0';
    in_is_word  <= '1' when i_funct3 = FUNCT3_LW else '0';
    in_is_sh    <= '1' when i_funct3 = FUNCT3_SH else '0';

    in_unaligned <= (in_is_load and ((in_is_word and (i_ea(1) or i_ea(0))) or (in_is_half and i_ea(0)))) or
                    (in_is_store and ((in_is_word and (i_ea(1) or i_ea(0))) or (in_is_sh and i_ea(0))));

    in_crossing <= (in_is_load and ((in_is_word and (i_ea(1) or i_ea(0))) or (in_is_half and i_ea(1) and i_ea(0)))) or
                   (in_is_store and ((in_is_word and (i_ea(1) or i_ea(0))) or (in_is_sh and i_ea(1) and i_ea(0))));

    gen_ea_trap : if HAS_ZICSR generate
        in_ea_xlast <= in_crossing when HAS_ZICCLSM else in_unaligned;
        in_ea_unal  <= in_unaligned;
        in_ea_stf   <= in_is_store when HAS_ACCESS_FAULTS else '0';
    end generate gen_ea_trap;

    gen_no_ea_trap : if not HAS_ZICSR generate
        in_ea_xlast <= '0';
        in_ea_unal  <= '0';
        in_ea_stf   <= '0';
    end generate gen_no_ea_trap;

    p_reg_ex_mem_ctrl_proc : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' or i_flush = '1' then
                r_valid      <= '0';
                r_rd         <= (others => '0');
                r_we_reg     <= '0';
                r_we_ok      <= '0';
                r_we_ram     <= '0';
                r_re_ram     <= '0';
                r_ld         <= '0';
                r_en_ram     <= '0';
                r_ext_ram_op <= (others => '0');
                r_wb_sel     <= (others => '0');
                r_is_flash   <= '0';
                r_is_sdram   <= '0';
                r_is_bus_mem <= '0';
                r_in_main    <= '0';
                r_last       <= '0';
                r_ok_wr      <= '1';
                r_cross      <= '0';
                r_ea_xlast   <= '0';
                r_ea_unal    <= '0';
                r_ea_stf     <= '0';
            elsif i_en = '1' then
                r_valid      <= i_valid;
                r_rd         <= i_rd;
                r_we_reg     <= i_we_reg;
                r_we_ok      <= i_we_reg and i_valid;
                r_we_ram     <= i_we_ram;
                r_re_ram     <= i_re_ram;
                r_ld         <= i_re_ram and in_rd_nz;
                r_en_ram     <= i_en_ram;
                r_ext_ram_op <= i_ext_ram_op;
                r_wb_sel     <= i_wb_sel;
                r_is_flash   <= in_is_flash;
                r_is_sdram   <= in_is_sdram;
                r_is_bus_mem <= in_is_bus_mem;
                r_in_main    <= in_in_main;
                r_last       <= in_last;
                r_ok_wr      <= in_ok_wr;
                r_cross      <= in_cross;
                r_ea_xlast   <= in_ea_xlast;
                r_ea_unal    <= in_ea_unal;
                r_ea_stf     <= in_ea_stf;
            end if;
        end if;

    end process p_reg_ex_mem_ctrl_proc;

    p_reg_ex_mem_data_proc : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_en = '1' then
                r_pc         <= i_pc;
                r_funct3     <= i_funct3;
                r_alu_out    <= i_alu_out;
                r_store_data <= i_store_data;
                r_byte_mask  <= i_byte_mask;
            end if;
        end if;

    end process p_reg_ex_mem_data_proc;

    o_valid       <= r_valid;
    o_pc          <= r_pc;
    o_funct3      <= r_funct3;
    o_alu_out     <= r_alu_out;
    o_store_data  <= r_store_data;
    o_byte_mask   <= r_byte_mask;
    o_rd          <= r_rd;
    o_we_reg      <= r_we_reg;
    o_we_ok       <= r_we_ok;
    o_we_ram      <= r_we_ram;
    o_re_ram      <= r_re_ram;
    o_ld          <= r_ld;
    o_en_ram      <= r_en_ram;
    o_ext_ram_op  <= r_ext_ram_op;
    o_wb_sel      <= r_wb_sel;
    o_is_flash    <= r_is_flash;
    o_is_sdram    <= r_is_sdram;
    o_is_bus_mem  <= r_is_bus_mem;
    o_in_main     <= r_in_main;
    -- As duas palavras de um acesso que cruza ficam na mesma região quando o endereço está na memória principal e não
    -- na última palavra dela; a combinação sai em MEM, um nível depois dos registradores.
    o_same_region <= r_in_main and (not r_last);
    o_ok_wr       <= r_ok_wr;
    o_cross       <= r_cross;
    o_ea_xlast    <= r_ea_xlast;
    o_ea_unal     <= r_ea_unal;
    o_ea_stf      <= r_ea_stf;

end architecture rtl;
