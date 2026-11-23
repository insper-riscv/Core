-- =============================================================================
-- Unidade de busca e atualização do Program Counter (estágio IF)
--
-- Mantém o registrador de Program Counter (PC), calcula combinacionalmente
-- PC + 4 via somador (adder) e seleciona o próximo endereço do PC via
-- multiplexador 4x1 (mux_4x1) de acordo com i_pc_src:
--   - PC_SRC_PC4      ("00") -> PC + 4 (fluxo sequencial normal)
--   - PC_SRC_BRANCH   ("01") -> i_branch_target (branch tomado ou JAL)
--   - PC_SRC_JALR     ("10") -> i_jalr_target (salto indireto JALR)
--   - PC_SRC_REDIRECT ("11") -> i_redirect_pc (trap, MRET ou FENCE.I; tem
--                               prioridade sobre congelamento de stall)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.config_pkg.all;
use work.pipeline_types.all;
use work.pc_src_consts.all;
use work.word_consts.all;

entity pc_fetch is
    generic (
        -- Endereço adiantado das memórias de instrução: o_addr_nx traz o endereço que o PC terá no ciclo seguinte, sem
        -- a decisão tardia de EX (desvio, salto, exceção, MRET, FENCE.I), e a busca da instrução do alvo toma um ciclo
        -- a mais (o PC fica parado no alvo um ciclo, enquanto as memórias leem o endereço novo). Com false, o_addr_nx é o
        -- próprio PC e nada muda.
        early_addr      : boolean := false
    );
    port (
        -- Sinal de clock.
        i_clk           : in    std_logic;
        -- Sinal de reset síncrono ativo em '1'.
        i_rst           : in    std_logic;
        -- Habilita a atualização do registrador PC ('1' = avança, '0' = congela em stall).
        i_pc_we         : in    std_logic;
        -- Seletor de 2 bits da fonte do próximo PC (definido em pc_src_consts).
        i_pc_src        : in    pc_src_t;
        -- Endereço-alvo de desvio condicional ou JAL calculado no estágio EX (PC + imm).
        i_branch_target : in    word_t;
        -- Endereço-alvo de salto indireto JALR calculado no estágio EX ((rs1 + imm) & ~1).
        i_jalr_target   : in    word_t;
        -- Endereço de redirecionamento prioritário para trap, MRET ou FENCE.I.
        i_redirect_pc   : in    word_t    := (others => '0');
        -- Repete a busca de uma instrução que a cache de instruções não tinha: com i_pc_src em PC + 4, o próximo PC é
        -- i_replay_pc.
        i_replay        : in    std_logic := '0';
        -- Endereço da instrução a repetir (o PC da instrução que está em IF/ID).
        i_replay_pc     : in    word_t    := (others => '0');
        -- Desvio ou salto decidido no estágio EX e liberado pelo pipeline, a decisão que chega mais tarde no ciclo: carrega o
        -- alvo e liga a escrita do PC, sem passar pela seleção de i_pc_src, e perde para o redirecionamento.
        i_late_take     : in    std_logic := '0';
        -- O alvo de i_late_take é o do JALR (i_jalr_target) em vez do desvio ou JAL (i_branch_target).
        i_late_jalr     : in    std_logic := '0';
        -- Valor atual do PC enviado ao barramento de busca e ao registrador IF/ID.
        o_pc            : out   word_t;
        -- Valor de PC + 4 enviado ao registrador de estágio IF/ID.
        o_pc4           : out   word_t;
        -- Endereço que as memórias de instrução leem na borda deste ciclo, o PC do ciclo seguinte (com early_addr), ou o
        -- PC atual (sem ele).
        o_addr_nx       : out   word_t;
        -- O PC foi carregado com um alvo de EX na borda anterior: as memórias leram o endereço sequencial, a instrução
        -- deste ciclo não vale e o PC fica parado (com early_addr; sempre '0' sem ele).
        o_late_q        : out   std_logic
    );
end entity pc_fetch;

architecture rtl of pc_fetch is

    -- Valor atual armazenado no registrador de Program Counter.
    signal pc_reg   : word_t;
    -- Resultado combinacional da soma PC + 4.
    signal pc4_wire : word_t;
    -- Entrada sequencial do multiplexador do PC: PC + 4, ou o endereço da instrução a repetir.
    signal seq_next : word_t;
    -- Próximo endereço selecionado pelo multiplexador de entrada do PC.
    signal pc_next  : word_t;
    -- Habilitação efetiva de atualização do registrador PC.
    signal pc_en    : std_logic;
    -- Alvo do desvio ou salto decidido tarde em EX.
    signal late_target : word_t;
    -- O redirecionamento prioritário está selecionado.
    signal redirect_sel : std_logic;
    -- Próximo PC sem a decisão tardia de EX.
    signal early_next : word_t;
    -- O PC foi carregado com um alvo de EX na borda anterior.
    signal late_q     : std_logic := '0';
    -- Habilitação de avanço do PC, sem o ciclo parado depois de um alvo de EX.
    signal pc_we_eff  : std_logic;
    -- Endereço sequencial do ciclo seguinte (PC + 4, a repetição ou o PC parado).
    signal addr_seq   : word_t;

begin

    -- Somador combinacional para cálculo de PC + 4.
    u_pc4_adder : entity work.adder
        generic map (
            data_width => word_t'length
        )
        port map (
            i_a => pc_reg,
            i_b => INSTR_BYTES,
            o_d => pc4_wire
        );

    seq_next <= i_replay_pc when i_replay = '1' else pc4_wire;

    -- Multiplexador 4x1 de seleção do próximo valor do PC.
    u_pc_mux : entity work.mux_4x1
        generic map (
            data_width => word_t'length
        )
        port map (
            i_d0  => seq_next,
            i_d1  => i_branch_target,
            i_d2  => i_jalr_target,
            i_d3  => i_redirect_pc,
            i_sel => i_pc_src,
            o_d   => early_next
        );

    redirect_sel <= '1' when i_pc_src = PC_SRC_REDIRECT else '0';
    late_target  <= i_jalr_target when i_late_jalr = '1' else i_branch_target;

    -- A decisão de EX é a última a chegar: entra só no seletor final e na habilitação, que não dependem dela nos
    -- demais termos.
    pc_next <= late_target when (i_late_take = '1' and redirect_sel = '0') else early_next;

    -- Com o endereço adiantado, o ciclo depois de um alvo de EX leu o endereço sequencial (a decisão chegou tarde
    -- demais para o endereço das RAMs): o PC fica parado no alvo e as RAMs o leem de novo.
    pc_we_eff <= i_pc_we and (not late_q);
    pc_en     <= pc_we_eff or redirect_sel or i_late_take;

    gen_late : if early_addr generate
    begin

        p_late : process (i_clk) is
        begin

            if rising_edge(i_clk) then
                if i_rst = '1' then
                    -- a primeira instrução depois do reset também espera: as memórias leram PC + 4
                    late_q <= '1';
                else
                    late_q <= i_late_take or redirect_sel;
                end if;
            end if;

        end process p_late;

    end generate gen_late;

    gen_no_late : if not early_addr generate
    begin

        late_q <= '0';

    end generate gen_no_late;

    -- O que o PC vira sem a decisão de EX: parado, a repetição ou PC + 4.
    addr_seq  <= seq_next when pc_we_eff = '1' else pc_reg;
    o_addr_nx <= addr_seq when early_addr else pc_reg;
    o_late_q  <= late_q;

    -- Registrador estrutural de 32 bits do Program Counter.
    u_pc_reg : entity work.generic_register
        generic map (
            data_width => word_t'length
        )
        port map (
            i_clk    => i_clk,
            i_rst    => i_rst,
            i_enable => pc_en,
            i_d      => pc_next,
            o_d      => pc_reg
        );

    o_pc  <= pc_reg;
    o_pc4 <= pc4_wire;

end architecture rtl;
