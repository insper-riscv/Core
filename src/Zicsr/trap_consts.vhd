-- =============================================================================
-- Constantes das instruções privilegiadas e das causas de exceção síncrona
--
-- IMM12_* são os valores do campo funct12 (bits [31:20]) das instruções SYSTEM
-- sem acesso a CSR (ECALL, EBREAK, WFI e MRET). CAUSE_* são os códigos gravados
-- em mcause para cada exceção síncrona, conforme o volume II da especificação
-- do RISC-V (The RISC-V Instruction Set Manual, Volume II: Privileged
-- Architecture).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;

package trap_consts is

    -- Campo funct12 da instrução ECALL (0x000).
    constant IMM12_ECALL  : std_logic_vector(11 downto 0) := x"000";
    -- Campo funct12 da instrução EBREAK (0x001).
    constant IMM12_EBREAK : std_logic_vector(11 downto 0) := x"001";
    -- Campo funct12 da instrução WFI (0x105).
    constant IMM12_WFI    : std_logic_vector(11 downto 0) := x"105";
    -- Campo funct12 da instrução MRET (0x302).
    constant IMM12_MRET   : std_logic_vector(11 downto 0) := x"302";

    -- Código mcause para endereço de instrução desalinhado (0).
    constant CAUSE_MISALIGNED_PC : word_t := std_logic_vector(to_unsigned(0, XLEN));
    -- Código mcause para falha de acesso de instrução (1).
    constant CAUSE_FETCH_FAULT   : word_t := std_logic_vector(to_unsigned(1, XLEN));
    -- Código mcause para falha de acesso de load (5).
    constant CAUSE_LOAD_FAULT    : word_t := std_logic_vector(to_unsigned(5, XLEN));
    -- Código mcause para falha de acesso de store ou AMO (7).
    constant CAUSE_STORE_FAULT   : word_t := std_logic_vector(to_unsigned(7, XLEN));
    -- Código mcause para instrução ilegal (2).
    constant CAUSE_ILLEGAL_INSTR : word_t := std_logic_vector(to_unsigned(2, XLEN));
    -- Código mcause para breakpoint EBREAK (3).
    constant CAUSE_BREAKPOINT    : word_t := std_logic_vector(to_unsigned(3, XLEN));
    -- Código mcause para endereço de load desalinhado (4).
    constant CAUSE_MISALIGNED_LD : word_t := std_logic_vector(to_unsigned(4, XLEN));
    -- Código mcause para endereço de store desalinhado (6).
    constant CAUSE_MISALIGNED_ST : word_t := std_logic_vector(to_unsigned(6, XLEN));
    -- Código mcause para chamada de ambiente do modo M, ECALL (11).
    constant CAUSE_MACHINE_ECALL : word_t := std_logic_vector(to_unsigned(11, XLEN));

end package trap_consts;
