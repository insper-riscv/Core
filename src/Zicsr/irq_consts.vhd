-- =============================================================================
-- Constantes das interrupções de máquina (mip, mie e mcause)
--
-- Posição de cada bit de interrupção de máquina em mip e mie, máscara dos bits
-- implementados e código de cada causa de interrupção gravado em mcause (bit 31
-- em '1'), conforme o volume II da especificação do RISC-V (The RISC-V
-- Instruction Set Manual, Volume II: Privileged Architecture).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;

package irq_consts is

    -- Posição do bit de interrupção de software de máquina (MSIP em mip, MSIE em mie).
    constant IRQ_BIT_SOFTWARE : natural := 3;
    -- Posição do bit de interrupção de timer de máquina (MTIP em mip, MTIE em mie).
    constant IRQ_BIT_TIMER    : natural := 7;
    -- Posição do bit de interrupção externa de máquina (MEIP em mip, MEIE em mie).
    constant IRQ_BIT_EXTERNAL : natural := 11;

    -- Posição do bit de interrupção de estouro de contador (LCOFIP em mip, LCOFIE em mie), da extensão Sscofpmf.
    constant IRQ_BIT_LCOFI : natural := 13;

    -- Índice de cada interrupção no vetor interno de 3 bits (software).
    constant IRQ_IDX_SOFTWARE : natural := 0;
    -- Índice de cada interrupção no vetor interno de 3 bits (timer).
    constant IRQ_IDX_TIMER    : natural := 1;
    -- Índice de cada interrupção no vetor interno de 3 bits (externa).
    constant IRQ_IDX_EXTERNAL : natural := 2;

    -- Largura do vetor interno de interrupções (software, timer e externa).
    constant IRQ_COUNT : natural := 3;

    -- Bit de interrupção do mcause, o mais significativo da palavra.
    constant CAUSE_IRQ_FLAG : word_t := std_logic_vector(shift_left(to_unsigned(1, XLEN), XLEN - 1));
    -- Código mcause da interrupção de software de máquina (bit de interrupção e código 3).
    constant CAUSE_IRQ_SOFTWARE : word_t := CAUSE_IRQ_FLAG or std_logic_vector(to_unsigned(3, XLEN));
    -- Código mcause da interrupção de timer de máquina (bit de interrupção e código 7).
    constant CAUSE_IRQ_TIMER    : word_t := CAUSE_IRQ_FLAG or std_logic_vector(to_unsigned(7, XLEN));
    -- Código mcause da interrupção externa de máquina (bit de interrupção e código 11).
    constant CAUSE_IRQ_EXTERNAL : word_t := CAUSE_IRQ_FLAG or std_logic_vector(to_unsigned(11, XLEN));
    -- Código mcause da interrupção de estouro de contador, LCOFI da Sscofpmf (bit de interrupção e código 13).
    constant CAUSE_IRQ_LCOFI    : word_t := CAUSE_IRQ_FLAG or std_logic_vector(to_unsigned(13, XLEN));

end package irq_consts;
