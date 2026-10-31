-- =============================================================================
-- Subtipos comuns de barramentos do pipeline RV32IM
--
-- Centraliza as larguras padrão de palavras de dados, endereços de
-- registradores, códigos de operação da ULA/extensores, seletores de
-- write-back e máscaras de bytes utilizadas entre os estágios do pipeline.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package pipeline_types is

  -- Palavra de dados/instrução/endereço de 32 bits.
  subtype word_t    is std_logic_vector(31 downto 0);

  -- Campo opcode da instrução RISC-V (bits [6:0], 7 bits).
  subtype opcode_t  is std_logic_vector(6 downto 0);
  -- Campo funct3 da instrução RISC-V (bits [14:12], 3 bits).
  subtype funct3_t  is std_logic_vector(2 downto 0);
  -- Campo funct7 da instrução RISC-V (bits [31:25], 7 bits).
  subtype funct7_t  is std_logic_vector(6 downto 0);

  -- Índice de registrador de uso geral (x0 a x31, 5 bits).
  subtype reg_t     is std_logic_vector(4 downto 0);
  -- Índice do registrador arquitetural x0 (sempre zero).
  constant REG_ZERO : reg_t := "00000";
  
  -- Código de operação da ULA (5 bits).
  subtype alu_op_t  is std_logic_vector(4 downto 0);

  -- Seleção one-hot do resultado de dados da ULA (8 bits), decodificada no estágio ID a partir de alu_op_t.
  subtype alu_sel_t is std_logic_vector(7 downto 0);

  -- Seletor de formato do extensor de imediato (3 bits).
  subtype ext_imm_op_t is std_logic_vector(2 downto 0);

  -- Seletor de modo de extensão de leitura da memória de dados (3 bits).
  subtype ext_ram_op_t is std_logic_vector(2 downto 0);

  -- Seletor de fonte para escrita no estágio WB (1 bit: 0 = resultado de EX, 1 = dado lido da memória).
  subtype wb_sel_t     is std_logic_vector(0 downto 0);

  -- Seletor de fonte do próximo valor de PC no estágio IF (2 bits).
  subtype pc_src_t     is std_logic_vector(1 downto 0);
  
  -- Máscara de habilitação de escrita por byte (4 bits).
  subtype byte_mask_t  is std_logic_vector(3 downto 0);

end package pipeline_types;
