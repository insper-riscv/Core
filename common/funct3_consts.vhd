-- =============================================================================
-- Constantes de funct3 (bits [14:12]) da arquitetura RISC-V RV32IM + Zicsr/Zifencei
--
-- Agrupa os códigos de subfunção de 3 bits por família de instrução para
-- decodificação legível e sem literais mágicos.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package funct3_consts is

  ------------------------------------------------------------------
  -- OP-IMM / OP (ALU I-type e R-type) funct3[2:0]
  ------------------------------------------------------------------
  -- Soma ou subtração registrador-registrador (ADD / SUB).
  constant FUNCT3_ADD_SUB  : funct3_t := "000";
  -- Soma com imediato (ADDI).
  constant FUNCT3_ADDI     : funct3_t := "000";
  -- Deslocamento lógico à esquerda por registrador (SLL).
  constant FUNCT3_SLL      : funct3_t := "001";
  -- Deslocamento lógico à esquerda por imediato (SLLI).
  constant FUNCT3_SLLI     : funct3_t := "001";
  -- Comparação menor-que com sinal por registrador (SLT).
  constant FUNCT3_SLT      : funct3_t := "010";
  -- Comparação menor-que com sinal por imediato (SLTI).
  constant FUNCT3_SLTI     : funct3_t := "010";
  -- Comparação menor-que sem sinal por registrador (SLTU).
  constant FUNCT3_SLTU     : funct3_t := "011";
  -- Comparação menor-que sem sinal por imediato (SLTIU).
  constant FUNCT3_SLTIU    : funct3_t := "011";
  -- OU exclusivo bit a bit por registrador (XOR).
  constant FUNCT3_XOR      : funct3_t := "100";
  -- OU exclusivo bit a bit por imediato (XORI).
  constant FUNCT3_XORI     : funct3_t := "100";
  -- Deslocamento à direita lógico ou aritmético por registrador (SRL / SRA).
  constant FUNCT3_SRL_SRA  : funct3_t := "101";
  -- Deslocamento à direita lógico ou aritmético por imediato (SRLI / SRAI).
  constant FUNCT3_SRLI_SRAI: funct3_t := "101";
  -- OU inclusivo bit a bit por registrador (OR).
  constant FUNCT3_OR       : funct3_t := "110";
  -- OU inclusivo bit a bit por imediato (ORI).
  constant FUNCT3_ORI      : funct3_t := "110";
  -- E lógico bit a bit por registrador (AND).
  constant FUNCT3_AND      : funct3_t := "111";
  -- E lógico bit a bit por imediato (ANDI).
  constant FUNCT3_ANDI     : funct3_t := "111";

  ------------------------------------------------------------------
  -- BRANCH (B-type) funct3[2:0]
  ------------------------------------------------------------------
  -- Desvio condicional se igual (BEQ).
  constant FUNCT3_BEQ      : funct3_t := "000";
  -- Desvio condicional se diferente (BNE).
  constant FUNCT3_BNE      : funct3_t := "001";
  -- Desvio condicional se menor com sinal (BLT).
  constant FUNCT3_BLT      : funct3_t := "100";
  -- Desvio condicional se maior ou igual com sinal (BGE).
  constant FUNCT3_BGE      : funct3_t := "101";
  -- Desvio condicional se menor sem sinal (BLTU).
  constant FUNCT3_BLTU     : funct3_t := "110";
  -- Desvio condicional se maior ou igual sem sinal (BGEU).
  constant FUNCT3_BGEU     : funct3_t := "111";

  ------------------------------------------------------------------
  -- LOAD funct3[2:0]
  ------------------------------------------------------------------
  -- Leitura de byte (8 bits) com extensão de sinal (LB).
  constant FUNCT3_LB       : funct3_t := "000";
  -- Leitura de meia-palavra (16 bits) com extensão de sinal (LH).
  constant FUNCT3_LH       : funct3_t := "001";
  -- Leitura de palavra completa de 32 bits (LW).
  constant FUNCT3_LW       : funct3_t := "010";
  -- Leitura de byte (8 bits) com extensão por zero (LBU).
  constant FUNCT3_LBU      : funct3_t := "100";
  -- Leitura de meia-palavra (16 bits) com extensão por zero (LHU).
  constant FUNCT3_LHU      : funct3_t := "101";

  ------------------------------------------------------------------
  -- STORE (S-type) funct3[2:0]
  ------------------------------------------------------------------
  -- Escrita de byte (8 bits) em memória (SB).
  constant FUNCT3_SB       : funct3_t := "000";
  -- Escrita de meia-palavra (16 bits) em memória (SH).
  constant FUNCT3_SH       : funct3_t := "001";
  -- Escrita de palavra completa (32 bits) em memória (SW).
  constant FUNCT3_SW       : funct3_t := "010";

  ------------------------------------------------------------------
  -- JALR funct3[2:0]
  ------------------------------------------------------------------
  -- Subfunção padrão da instrução JALR.
  constant FUNCT3_JALR     : funct3_t := "000";

  ------------------------------------------------------------------
  -- Extensao M (OP com funct7 = "0000001") funct3[2:0]
  ------------------------------------------------------------------
  -- Multiplicação (32 bits inferiores do produto, MUL).
  constant FUNCT3_MUL      : funct3_t := "000";
  -- Multiplicação signed x signed (32 bits superiores, MULH).
  constant FUNCT3_MULH     : funct3_t := "001";
  -- Multiplicação signed x unsigned (32 bits superiores, MULHSU).
  constant FUNCT3_MULHSU   : funct3_t := "010";
  -- Multiplicação unsigned x unsigned (32 bits superiores, MULHU).
  constant FUNCT3_MULHU    : funct3_t := "011";
  -- Quociente da divisão inteira com sinal (DIV).
  constant FUNCT3_DIV      : funct3_t := "100";
  -- Quociente da divisão inteira sem sinal (DIVU).
  constant FUNCT3_DIVU     : funct3_t := "101";
  -- Resto da divisão inteira com sinal (REM).
  constant FUNCT3_REM      : funct3_t := "110";
  -- Resto da divisão inteira sem sinal (REMU).
  constant FUNCT3_REMU     : funct3_t := "111";

  ------------------------------------------------------------------
  -- MISC-MEM (FENCE / FENCE.I) funct3[2:0]
  ------------------------------------------------------------------
  -- Barreira de ordenação de acessos à memória de dados (FENCE).
  constant FUNCT3_FENCE    : funct3_t := "000";
  -- Barreira de sincronização do fluxo de instruções (FENCE.I).
  constant FUNCT3_FENCE_I  : funct3_t := "001";

  ------------------------------------------------------------------
  -- SYSTEM (Priv / CSR) funct3[2:0]
  ------------------------------------------------------------------
  -- Instruções privilegiadas sem acesso direto a CSR (ECALL, EBREAK, MRET).
  constant FUNCT3_PRIV     : funct3_t := "000";
  -- Subfunção reservada da classe SYSTEM (nem privilegiada nem acesso a CSR).
  constant FUNCT3_SYSTEM_RESERVED : funct3_t := "100";
  -- Leitura e escrita atômica em CSR via registrador (CSRRW).
  constant FUNCT3_CSRRW    : funct3_t := "001";
  -- Leitura e set de bits atômico em CSR via registrador (CSRRS).
  constant FUNCT3_CSRRS    : funct3_t := "010";
  -- Leitura e clear de bits atômico em CSR via registrador (CSRRC).
  constant FUNCT3_CSRRC    : funct3_t := "011";
  -- Leitura e escrita atômica em CSR via imediato de 5 bits (CSRRWI).
  constant FUNCT3_CSRRWI   : funct3_t := "101";
  -- Leitura e set de bits atômico em CSR via imediato de 5 bits (CSRRSI).
  constant FUNCT3_CSRRSI   : funct3_t := "110";
  -- Leitura e clear de bits atômico em CSR via imediato de 5 bits (CSRRCI).
  constant FUNCT3_CSRRCI   : funct3_t := "111";

end package funct3_consts;
