-- =============================================================================
-- Constantes de funct7 (bits [31:25]) da arquitetura RISC-V RV32IM
--
-- Define os campos funct7 utilizados para diferenciar operações aritméticas
-- e lógicas base (ADD vs SUB, SRL vs SRA) das instruções de multiplicação e
-- divisão inteira da extensão M (MULDIV).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package funct7_consts is

  ------------------------------------------------------------------
  -- Grupos gerais de funct7[6:0]
  ------------------------------------------------------------------
  -- Valor padrão de funct7 para instruções RV32I base.
  constant FUNCT7_DEFAULT : funct7_t := "0000000";
  -- Valor alternativo de funct7 (seleciona SUB e deslocamento aritmético SRA/SRAI).
  constant FUNCT7_ALT     : funct7_t := "0100000";
  -- Valor de funct7 que identifica instruções da extensão M (MUL/DIV/REM).
  constant FUNCT7_MULDIV  : funct7_t := "0000001";

  ------------------------------------------------------------------
  -- OP-IMM (shifts imediatos: SLLI, SRLI, SRAI) funct7[6:0]
  ------------------------------------------------------------------
  -- Campo funct7 da instrução SLLI.
  constant FUNCT7_SLLI    : funct7_t := "0000000";
  -- Campo funct7 da instrução SRLI.
  constant FUNCT7_SRLI    : funct7_t := "0000000";
  -- Campo funct7 da instrução SRAI.
  constant FUNCT7_SRAI    : funct7_t := "0100000";

  ------------------------------------------------------------------
  -- OP (R-type RV32I) funct7[6:0]
  ------------------------------------------------------------------
  -- Campo funct7 da instrução SUB.
  constant FUNCT7_SUB     : funct7_t := "0100000";
  -- Campo funct7 da instrução SRA.
  constant FUNCT7_SRA     : funct7_t := "0100000";

end package funct7_consts;
