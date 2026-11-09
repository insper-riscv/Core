-- =============================================================================
-- Banco de contadores de eventos da extensão Zihpm
--
-- Guarda, para cada índice de 3 a 2 + hpm_counters, o seletor de evento
-- (mhpmeventN, 4 bits), o bit de inibição (bit N de mcountinhibit) e um
-- contador de hpm_width bits (mhpmcounterN e mhpmcounterNh). Cada contador tem
-- o seu próprio incrementador, com vai-um registrado entre as metades, e soma 1
-- a cada ciclo em que o evento escolhido vale '1' em i_events, o código vale
-- diferente de 0 e o bit de inibição está em '0'. Um código fora da tabela de
-- eventos não conta. Uma escrita explícita na metade de um contador prevalece
-- sobre a soma do mesmo ciclo.
--
-- O banco é endereçado como os CSRs: i_idx são os 5 bits baixos do endereço e
-- os quatro seletores de faixa dizem se o acesso é a mcountinhibit, a um
-- seletor de evento, a uma metade baixa ou a uma metade alta; o espelho de
-- leitura hpmcounterN usa as mesmas seleções de leitura do contador de máquina.
-- Os índices abaixo de 3 e os de hpm_counters em diante leem zero e ignoram a
-- escrita, e hpm_width igual a 0 deixa o banco sem nenhum contador real. Os bits
-- de um contador acima de hpm_width leem zero.
--
-- Com HAS_SSCOFPMF = true (extensão Sscofpmf) cada contador ganha também a metade alta do seletor (mhpmeventNh) com
-- dois bits: OF (bit 31, estouro, que pega quando o contador estoura e só a escrita do programa limpa) e MINH (bit 30,
-- inibe a contagem no modo máquina, o único que o núcleo tem). Quando um contador estoura com OF em '0' o banco
-- pulsa o_ovf_irq (o pedido de interrupção de estouro) e o OF passa a '1'; com OF em '1' o estouro não pede nada, de
-- modo que o OF também desabilita a interrupção do contador. Uma escrita nunca estoura o contador. Sem a extensão a
-- faixa de mhpmeventNh não existe e o_ovf_irq vale '0'.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;
use work.csr_addr_consts.all;
use work.csr_event_consts.all;
use work.utils_pkg.all;

entity hpm_counter_bank is
    generic (
        -- Quantidade de contadores de eventos reais, de índices 3 a 2 + hpm_counters.
        hpm_counters    : natural range 0 to HPM_MAX_COUNTERS := HPM_MAX_COUNTERS;
        -- Largura em bits de cada contador (0 deixa o banco sem contadores reais).
        hpm_width       : natural range 0 to 64               := 64;
        -- A leitura sai de um registrador: o_rdata mostra, um ciclo depois, o valor do endereço dado em i_idx e nos seletores (a leitura dos 29 contadores sai do caminho combinacional do núcleo).
        registered_read : boolean                             := false
    );
    port (
        -- Sinal de clock do sistema.
        i_clk         : in    std_logic;
        -- Reset ativo em '1'.
        i_rst         : in    std_logic;
        -- Vetor de eventos: o bit K vale '1' nos ciclos em que o evento de código K ocorre.
        i_events      : in    std_logic_vector(EVENT_VECTOR_WIDTH - 1 downto 0);
        -- Índice do CSR dentro da faixa (bits [4:0] do endereço).
        i_idx         : in    std_logic_vector(4 downto 0);
        -- O acesso é a mcountinhibit (faixa dos seletores de evento, índice 0).
        i_sel_inhibit : in    std_logic;
        -- O acesso é à faixa dos seletores de evento mhpmeventN.
        i_sel_event   : in    std_logic;
        -- O acesso é à faixa das metades altas dos seletores de evento (mhpmeventNh), só com HAS_SSCOFPMF.
        i_sel_eventh  : in    std_logic := '0';
        -- O acesso é à faixa das metades baixas (mhpmcounterN ou hpmcounterN).
        i_sel_lo      : in    std_logic;
        -- O acesso é à faixa das metades altas (mhpmcounterNh ou hpmcounterNh).
        i_sel_hi      : in    std_logic;
        -- Escrita efetiva de uma instrução CSR neste ciclo, sempre numa faixa que aceita escrita.
        i_we          : in    std_logic;
        -- Valor escrito no registrador selecionado.
        i_wdata       : in    word_t;
        -- Valor lido do registrador selecionado (zero se não for do banco).
        o_rdata       : out   word_t;
        -- Pedido de interrupção de estouro: algum contador estourou com o bit OF em '0' (sempre '0' sem HAS_SSCOFPMF).
        o_ovf_irq     : out   std_logic
    );
end entity hpm_counter_bank;

architecture rtl of hpm_counter_bank is

    -- Quantidade de contadores com registradores de fato: nenhum quando a largura é 0.

    function real_count return natural is
    begin

        if hpm_width = 0 then
            return 0;
        end if;

        return hpm_counters;

    end function real_count;

    -- Contadores reais do banco.
    constant REAL_COUNTERS : natural := real_count;

    -- Uma palavra de leitura por índice de CSR (0 a 31).
    subtype rows_t is word_array_t(HPM_LAST_INDEX downto 0)(word_t'length - 1 downto 0);

    -- Códigos de evento lidos de cada mhpmeventN, estendidos a uma palavra.
    signal event_rows   : rows_t;
    -- Metades baixas lidas de cada mhpmcounterN.
    signal lo_rows      : rows_t;
    -- Metades altas lidas de cada mhpmcounterNh.
    signal hi_rows      : rows_t;
    -- Metades altas lidas de cada mhpmeventNh (os bits OF e MINH).
    signal eventh_rows  : rows_t;
    -- Pedido de estouro de cada contador: estourou com o OF em '0'.
    signal ovf_req      : std_logic_vector(HPM_LAST_INDEX downto 0);
    -- Palavra lida da faixa das metades altas dos seletores de evento.
    signal eventh_word  : word_t;
    -- Palavra lida da faixa dos seletores de evento.
    signal event_word   : word_t;
    -- Palavra lida da faixa das metades baixas.
    signal lo_word      : word_t;
    -- Palavra lida da faixa das metades altas.
    signal hi_word      : word_t;
    -- Palavra lida de mcountinhibit (bits de 3 em diante, um por contador).
    signal inhibit_word : word_t;
    -- Bits de inibição, o bit K para o contador de índice K + 3.
    signal inhibit_q    : std_logic_vector(HPM_MAX_COUNTERS - 1 downto 0);
    -- Escrita em mcountinhibit.
    signal inhibit_we   : std_logic;
    -- Eventos da tabela, os únicos que um contador pode contar.
    signal events_valid : std_logic_vector(EVENT_VECTOR_WIDTH - 1 downto 0);
    -- Valor lido combinacionalmente do contador, do evento ou da inibição selecionado.
    signal rdata_comb   : word_t;
    -- Valor lido, registrado (com registered_read).
    signal rdata_q      : word_t := (others => '0');

begin

    events_valid <= i_events and EVENT_TABLE_MASK;

    -- mcountinhibit: os bits de 0 a 2 não pertencem ao banco e leem zero aqui.
    inhibit_word(2 downto 0)  <= (others => '0');
    inhibit_word(31 downto 3) <= inhibit_q;
    inhibit_we                <= i_we and i_sel_inhibit;

    inhibit_q(HPM_MAX_COUNTERS - 1 downto REAL_COUNTERS) <= (others => '0');

    gen_inhibit : if REAL_COUNTERS > 0 generate

        u_inhibit : entity work.generic_register
            generic map (
                data_width => REAL_COUNTERS
            )
            port map (
                i_clk    => i_clk,
                i_rst    => i_rst,
                i_enable => inhibit_we,
                i_d      => i_wdata(HPM_FIRST_INDEX + REAL_COUNTERS - 1 downto HPM_FIRST_INDEX),
                o_d      => inhibit_q(REAL_COUNTERS - 1 downto 0)
            );

    end generate gen_inhibit;

    gen_index : for n in 0 to HPM_LAST_INDEX generate

        -- Índice sem contador real: lê zero e ignora a escrita.

        gen_absent : if n < HPM_FIRST_INDEX or n >= HPM_FIRST_INDEX + REAL_COUNTERS generate
            event_rows(n)  <= (others => '0');
            lo_rows(n)     <= (others => '0');
            hi_rows(n)     <= (others => '0');
            eventh_rows(n) <= (others => '0');
            ovf_req(n)     <= '0';
        end generate gen_absent;

        gen_present : if n >= HPM_FIRST_INDEX and n < HPM_FIRST_INDEX + REAL_COUNTERS generate
            -- Índice do contador, nos 5 bits baixos do endereço.
            constant INDEX     : std_logic_vector(4 downto 0) := std_logic_vector(to_unsigned(n, 5));
            -- Código de evento escolhido para este contador.
            signal   code      : std_logic_vector(EVENT_CODE_WIDTH - 1 downto 0);
            -- O acesso deste ciclo é a este índice.
            signal   hit       : std_logic;
            -- Escrita no seletor de evento.
            signal   event_we  : std_logic;
            -- Escrita na metade baixa.
            signal   lo_we     : std_logic;
            -- Escrita na metade alta.
            signal   hi_we     : std_logic;
            -- O evento escolhido ocorre e o contador não está inibido.
            signal   inc       : std_logic;
            -- Pulso de estouro do contador.
            signal   wrap      : std_logic;
            -- Bit OF do seletor: o contador estourou e o programa ainda não limpou.
            signal   of_q      : std_logic;
            -- Bit MINH do seletor: a contagem no modo máquina está inibida.
            signal   minh_q    : std_logic;
            -- Escrita na metade alta do seletor de evento.
            signal   eventh_we : std_logic;
            -- Próximo valor do bit OF: o estouro põe '1' e a escrita do programa traz o bit 31.
            signal   of_d      : std_logic;
            -- Habilitação do bit OF: o estouro ou a escrita do programa.
            signal   of_en     : std_logic;
            -- Metade baixa do contador.
            signal   lo        : word_t;
            -- Metade alta do contador.
            signal   hi        : word_t;
        begin

            hit      <= '1' when i_idx = INDEX else '0';
            event_we <= i_we and i_sel_event and hit;
            lo_we    <= i_we and i_sel_lo and hit;
            hi_we    <= i_we and i_sel_hi and hit;

            u_event_code : entity work.generic_register
                generic map (
                    data_width => EVENT_CODE_WIDTH
                )
                port map (
                    i_clk    => i_clk,
                    i_rst    => i_rst,
                    i_enable => event_we,
                    i_d      => i_wdata(EVENT_CODE_WIDTH - 1 downto 0),
                    o_d      => code
                );

            -- O bit 0 do vetor válido é sempre zero, então o código 0 nunca conta.
            inc <= events_valid(to_integer(unsigned(code))) and (not inhibit_q(n - HPM_FIRST_INDEX)) and (not minh_q);

            u_counter : entity work.counter64
                generic map (
                    width => hpm_width
                )
                port map (
                    i_clk   => i_clk,
                    i_rst   => i_rst,
                    i_inc   => inc,
                    i_we_lo => lo_we,
                    i_we_hi => hi_we,
                    i_wdata => i_wdata,
                    o_lo    => lo,
                    o_hi    => hi,
                    o_wrap  => wrap
                );

            gen_sscofpmf : if HAS_SSCOF generate
                eventh_we <= i_we and i_sel_eventh and hit;
                of_d      <= wrap or i_wdata(31);
                of_en     <= wrap or eventh_we;

                -- O estouro põe OF em '1' mesmo que o programa escreva '0' no mesmo ciclo; a escrita do programa limpa ou põe o OF.
                u_of : entity work.flip_flop
                    port map (
                        i_d      => of_d,
                        o_d      => of_q,
                        i_enable => of_en,
                        i_clk    => i_clk,
                        i_rst    => i_rst
                    );

                u_minh : entity work.flip_flop
                    port map (
                        i_d      => i_wdata(30),
                        o_d      => minh_q,
                        i_enable => eventh_we,
                        i_clk    => i_clk,
                        i_rst    => i_rst
                    );

                ovf_req(n)     <= wrap and (not of_q);
                eventh_rows(n) <= (31 => of_q, 30 => minh_q, others => '0');
            end generate gen_sscofpmf;

            gen_no_sscofpmf : if not HAS_SSCOF generate
                eventh_we      <= '0';
                of_d           <= '0';
                of_en          <= '0';
                of_q           <= '0';
                minh_q         <= '0';
                ovf_req(n)     <= '0';
                eventh_rows(n) <= (others => '0');
            end generate gen_no_sscofpmf;

            event_rows(n) <= std_logic_vector(resize(unsigned(code), word_t'length));
            lo_rows(n)    <= lo;
            hi_rows(n)    <= hi;

        end generate gen_present;

    end generate gen_index;

    u_event_mux : entity work.mux_tree
        generic map (
            data_width     => word_t'length,
            selector_width => i_idx'length
        )
        port map (
            i_array => event_rows,
            i_sel   => i_idx,
            o_d     => event_word
        );

    u_lo_mux : entity work.mux_tree
        generic map (
            data_width     => word_t'length,
            selector_width => i_idx'length
        )
        port map (
            i_array => lo_rows,
            i_sel   => i_idx,
            o_d     => lo_word
        );

    -- A leitura de mhpmeventNh só existe com a extensão; sem ela as linhas valem zero e o multiplexador some na síntese.
    u_eventh_mux : entity work.mux_tree
        generic map (
            data_width     => word_t'length,
            selector_width => i_idx'length
        )
        port map (
            i_array => eventh_rows,
            i_sel   => i_idx,
            o_d     => eventh_word
        );

    o_ovf_irq <= '1' when ovf_req /= (ovf_req'range => '0') else '0';

    u_hi_mux : entity work.mux_tree
        generic map (
            data_width     => word_t'length,
            selector_width => i_idx'length
        )
        port map (
            i_array => hi_rows,
            i_sel   => i_idx,
            o_d     => hi_word
        );

    rdata_comb <= (event_word   and (word_t'range => i_sel_event)) or
	           (lo_word      and (word_t'range    => i_sel_lo)) or
	           (hi_word      and (word_t'range    => i_sel_hi)) or
	           (eventh_word  and (word_t'range    => i_sel_eventh)) or
	           (inhibit_word and (word_t'range    => i_sel_inhibit));

    gen_comb_read : if not registered_read generate
        o_rdata <= rdata_comb;
    end generate gen_comb_read;

    gen_registered_read : if registered_read generate

        process (i_clk) is
        begin

            if rising_edge(i_clk) then
                rdata_q <= rdata_comb;
            end if;

        end process;

        o_rdata <= rdata_q;
    end generate gen_registered_read;

end architecture rtl;
