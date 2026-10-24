-- =============================================================================
-- Constantes de código de operação da ULA (Unidade Lógica e Aritmética)
--
-- Define os seletores de 5 bits (ALU_*) utilizados pela entidade alu para
-- executar operações aritméticas, lógicas, deslocamentos, comparações e
-- avaliação de desvios condicionais da arquitetura RV32I.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package alu_consts is

	-- Repassa diretamente o operando B (i_b) para a saída (usado em LUI).
	constant ALU_PASS_B : std_logic_vector(4 downto 0) := "00000";
	-- Soma aritmética (i_a + i_b).
	constant ALU_ADD    : std_logic_vector(4 downto 0) := "00001";
	-- OU exclusivo bit a bit (i_a xor i_b).
	constant ALU_XOR    : std_logic_vector(4 downto 0) := "00010";
	-- OU inclusivo bit a bit (i_a or i_b).
	constant ALU_OR     : std_logic_vector(4 downto 0) := "00011";
	-- E lógico bit a bit (i_a and i_b).
	constant ALU_AND    : std_logic_vector(4 downto 0) := "00100";
	-- Deslocamento lógico à esquerda (SLL / SLLI).
	constant ALU_SLL    : std_logic_vector(4 downto 0) := "00101";
	-- Deslocamento lógico à direita (SRL / SRLI).
	constant ALU_SRL    : std_logic_vector(4 downto 0) := "00110";
	-- Deslocamento aritmético à direita com preservação de sinal (SRA / SRAI).
	constant ALU_SRA    : std_logic_vector(4 downto 0) := "00111";
	-- Subtração aritmética (i_a - i_b).
	constant ALU_SUB    : std_logic_vector(4 downto 0) := "01000";
	-- Comparação menor-que com sinal (SLT / SLTI).
	constant ALU_SLT    : std_logic_vector(4 downto 0) := "01001";
	-- Comparação menor-que sem sinal (SLTU / SLTIU).
	constant ALU_SLTU   : std_logic_vector(4 downto 0) := "01010";
	-- Comparação de igualdade para desvio condicional (BEQ).
	constant ALU_BEQ    : std_logic_vector(4 downto 0) := "01011";
	-- Comparação de diferença para desvio condicional (BNE).
	constant ALU_BNE    : std_logic_vector(4 downto 0) := "01100";
	-- Comparação menor-que com sinal para desvio condicional (BLT).
	constant ALU_BLT    : std_logic_vector(4 downto 0) := "01101";
	-- Comparação maior-ou-igual com sinal para desvio condicional (BGE).
	constant ALU_BGE    : std_logic_vector(4 downto 0) := "01110";
	-- Comparação menor-que sem sinal para desvio condicional (BLTU).
	constant ALU_BLTU   : std_logic_vector(4 downto 0) := "01111";
	-- Comparação maior-ou-igual sem sinal para desvio condicional (BGEU).
	constant ALU_BGEU   : std_logic_vector(4 downto 0) := "10000";
	-- Cálculo de endereço-alvo de salto indireto com bit menos significativo zerado (JALR).
	constant ALU_JALR   : std_logic_vector(4 downto 0) := "10001";

end package alu_consts;
