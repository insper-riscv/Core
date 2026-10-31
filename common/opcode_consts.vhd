-- =============================================================================
-- Constantes de opcode (bits [6:0]) da arquitetura RISC-V RV32IM + Zicsr/Zifencei
--
-- Centraliza os códigos de operação primários utilizados pelo decodificador de
-- instruções, unidade de controle e unidades de extensão do processador.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package opcode_consts is

  ------------------------------------------------------------------
  -- Prefixo de instrução de 32 bits
  ------------------------------------------------------------------
  -- Bits [1:0] de toda instrução de 32 bits (os outros valores indicam instrução comprimida, não suportada).
  constant OPCODE_LOW_BITS : std_logic_vector(1 downto 0) := "11";

  ------------------------------------------------------------------
  -- RV32I Base Opcodes [6:0]
  ------------------------------------------------------------------
  -- Instruções de leitura de memória (LB, LH, LW, LBU, LHU).
  constant OPCODE_LOAD     : opcode_t := "0000011";
  -- Instruções aritméticas/lógicas com imediato (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI).
  constant OPCODE_OP_IMM   : opcode_t := "0010011";
  -- Adição de imediato superior ao PC (AUIPC).
  constant OPCODE_AUIPC    : opcode_t := "0010111";
  -- Instruções de escrita em memória (SB, SH, SW).
  constant OPCODE_STORE    : opcode_t := "0100011";
  -- Instruções registrador-registrador RV32I e extensão M (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, MUL/DIV/REM).
  constant OPCODE_OP       : opcode_t := "0110011";
  -- Carregamento de imediato superior (LUI).
  constant OPCODE_LUI      : opcode_t := "0110111";
  -- Instruções de desvio condicional (BEQ, BNE, BLT, BGE, BLTU, BGEU).
  constant OPCODE_BRANCH   : opcode_t := "1100011";
  -- Salto incondicional indireto via registrador (JALR).
  constant OPCODE_JALR     : opcode_t := "1100111";
  -- Salto incondicional relativo ao PC (JAL).
  constant OPCODE_JAL      : opcode_t := "1101111";

  ------------------------------------------------------------------
  -- Zifencei / MISC-MEM Opcode [6:0]
  ------------------------------------------------------------------
  -- Instruções de sincronização de memória e cache de instruções (FENCE, FENCE.I).
  constant OPCODE_MISC_MEM : opcode_t := "0001111";

  ------------------------------------------------------------------
  -- Zicsr / SYSTEM Opcode [6:0]
  ------------------------------------------------------------------
  -- Instruções de sistema, privilégio e acesso a CSRs (ECALL, EBREAK, MRET, CSRRW/S/C/I).
  constant OPCODE_SYSTEM   : opcode_t := "1110011";

end package opcode_consts;
