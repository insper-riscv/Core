-- =============================================================================
-- Multiplicador combinacional pipelinado de 32 bits (Extensão RV32M)
--
-- Mesma interface e mesmo contrato do booth_multiplier_rv32: o produto de 64 bits de dois operandos de 32 bits com
-- sinal, dividido em parte baixa (o_result_lo, para MUL) e parte alta (o_result_hi, base de MULH, MULHSU e MULHU), com
-- um pulso de término (o_done). Em vez de 32 passos de soma e deslocamento, o produto sai de um multiplicador de
-- bloco DSP com três registradores em série, e a latência cai de 33 para 3 ciclos.
--
-- Linha do tempo (t0 é o ciclo do pulso de início):
--   t0     os operandos entram nos registradores de entrada (o_busy sobe já neste ciclo, como no Booth)
--   t0+1   o produto é calculado e registrado
--   t0+2   o produto segue para o registrador de saída
--   t0+3   o_done e o resultado válidos, e o resultado fica estável até o início seguinte
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;

entity dsp_multiplier_rv32 is
    port (
        -- Sinal de clock do sistema.
        i_clk          : in    std_logic;
        -- Sinal de reset síncrono ativo em '1'.
        i_rst          : in    std_logic;
        -- Pulso de início da multiplicação no estágio EX.
        i_start        : in    std_logic;
        -- Pulso que interrompe a operação em curso e volta ao repouso, sem produzir o_done (resultado já conhecido).
        i_abort        : in    std_logic := '0';
        -- Multiplicando de 32 bits (operando A / rs1).
        i_multiplicand : in    word_t;
        -- Multiplicador de 32 bits (operando B / rs2).
        i_multiplier   : in    word_t;
        -- Parte baixa do produto (bits [31:0], resultado da instrução MUL).
        o_result_lo    : out   word_t;
        -- Parte alta do produto (bits [63:32], base para MULH/MULHSU/MULHU).
        o_result_hi    : out   word_t;
        -- Pulso de 1 ciclo indicando que o produto de 64 bits está pronto.
        o_done         : out   std_logic;
        -- Indica que o multiplicador está ocupado processando uma operação.
        o_busy         : out   std_logic
    );
end entity dsp_multiplier_rv32;

architecture rtl of dsp_multiplier_rv32 is

    -- Pulso que aceita o início: o multiplicador está livre e o início anterior já foi liberado.
    signal start_ok    : std_logic;
    -- Primeira e segunda fases do cálculo: o produto sendo calculado e o produto seguindo para o registrador de saída.
    signal ph1_q       : std_logic;
    signal ph2_q       : std_logic;
    -- Ocupado durante os ciclos de cálculo.
    signal busy_q      : std_logic;
    -- Inibidor que impede reinício imediato caso i_start permaneça em '1' ao final.
    signal inhibit_q   : std_logic;
    -- Pulso de término registrado.
    signal done_q      : std_logic;
    -- Próximos valores dos sinais de controle.
    signal ph1_d       : std_logic;
    signal ph2_d       : std_logic;
    signal busy_d      : std_logic;
    signal inhibit_d   : std_logic;
    signal done_d      : std_logic;
    -- Operandos registrados.
    signal a_q         : word_t;
    signal b_q         : word_t;
    -- Produto de 64 bits antes do primeiro registrador.
    signal product     : std_logic_vector(2 * XLEN - 1 downto 0);
    -- Produto de 64 bits do primeiro registrador e do registrador de saída.
    signal p1_q        : std_logic_vector(2 * XLEN - 1 downto 0);
    signal p2_q        : std_logic_vector(2 * XLEN - 1 downto 0);

begin

    start_ok <= i_start and (not inhibit_q) and (not busy_q);

    -- O_busy sobe no mesmo ciclo de i_start em repouso (stall adiantado), como no Booth.
    o_busy <= start_ok or busy_q;
    o_done <= done_q;

    -- Um abortar zera as fases, o ocupado e o término; o inibidor segue a mesma regra do início.
    ph1_d     <= start_ok and (not i_abort);
    ph2_d     <= ph1_q and (not i_abort);
    done_d    <= ph2_q and (not i_abort);
    busy_d    <= (start_ok or (busy_q and (not ph2_q))) and (not i_abort);
    inhibit_d <= '1' when ph2_q = '1' else
                 '0' when (busy_q = '0' and i_start = '0') else
                 inhibit_q;

    u_ph1 : entity work.flip_flop
        port map (i_d => ph1_d, o_d => ph1_q, i_enable => '1', i_clk => i_clk, i_rst => i_rst);

    u_ph2 : entity work.flip_flop
        port map (i_d => ph2_d, o_d => ph2_q, i_enable => '1', i_clk => i_clk, i_rst => i_rst);

    u_busy : entity work.flip_flop
        port map (i_d => busy_d, o_d => busy_q, i_enable => '1', i_clk => i_clk, i_rst => i_rst);

    u_done : entity work.flip_flop
        port map (i_d => done_d, o_d => done_q, i_enable => '1', i_clk => i_clk, i_rst => i_rst);

    u_inhibit : entity work.flip_flop
        port map (i_d => inhibit_d, o_d => inhibit_q, i_enable => '1', i_clk => i_clk, i_rst => i_rst);

    -- Os operandos entram no início; o produto passa pelos dois registradores seguintes a cada ciclo, o que a síntese
    -- reconhece como um multiplicador com os registradores do bloco DSP.
    u_a : entity work.generic_register
        generic map (data_width => XLEN)
        port map (i_d => i_multiplicand, o_d => a_q, i_enable => start_ok, i_clk => i_clk, i_rst => i_rst);

    u_b : entity work.generic_register
        generic map (data_width => XLEN)
        port map (i_d => i_multiplier, o_d => b_q, i_enable => start_ok, i_clk => i_clk, i_rst => i_rst);

    product <= std_logic_vector(signed(a_q) * signed(b_q));

    u_p1 : entity work.generic_register
        generic map (data_width => 2 * XLEN)
        port map (i_d => product, o_d => p1_q, i_enable => '1', i_clk => i_clk, i_rst => i_rst);

    u_p2 : entity work.generic_register
        generic map (data_width => 2 * XLEN)
        port map (i_d => p1_q, o_d => p2_q, i_enable => '1', i_clk => i_clk, i_rst => i_rst);

    o_result_hi <= p2_q(2 * XLEN - 1 downto XLEN);
    o_result_lo <= p2_q(XLEN - 1 downto 0);

end architecture rtl;
