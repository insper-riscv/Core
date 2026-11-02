-- =============================================================================
-- Constantes de código de operação da ULA (alu_op_t)
--
-- Define os seletores de 5 bits (ALU_*) utilizados pela unidade de controle e
-- pela entidade alu. O código tem a mesma estrutura do funct3 do RISC-V, de modo
-- que a ULA seleciona o resultado sem recodificar:
--
--   bit 4     : classe de controle (JALR, LUI e os seis desvios).
--   bit 3     : inversão do operando B com carry-in 1 (subtração e comparações);
--               nos deslocamentos à direita, indica deslocamento aritmético.
--   bits 2..0 : seleção do resultado, igual ao funct3 das instruções de tipo R/I
--               (000 soma, 001 SLL, 010 SLT, 011 SLTU, 100 XOR, 101 desloca à
--               direita, 110 OR, 111 AND). Nos desvios, é o funct3 do desvio.
--
-- O estágio ID decodifica o código na seleção one-hot do resultado (alu_sel_t), que
-- viaja pelo registrador ID/EX e dispensa a decodificação dentro da ULA.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package alu_consts is

	-- Dígito de 2 bits da quantidade de deslocamento, que seleciona a entrada de um estágio de deslocamento 4 para 1.
	subtype shift_digit_t is std_logic_vector(1 downto 0);

	-- Dígito 0 do deslocamento: o estágio não desloca.
	constant SHIFT_DIGIT_0 : shift_digit_t := "00";
	-- Dígito 1 do deslocamento: o estágio desloca 1 * 4**p posições.
	constant SHIFT_DIGIT_1 : shift_digit_t := "01";
	-- Dígito 2 do deslocamento: o estágio desloca 2 * 4**p posições.
	constant SHIFT_DIGIT_2 : shift_digit_t := "10";

	-- Posição do bit de classe de controle em alu_op_t.
	constant ALU_BIT_CLASS : natural := 4;
	-- Posição do bit de inversão de B (subtração, comparação e deslocamento aritmético).
	constant ALU_BIT_INV   : natural := 3;

	-- Soma aritmética (i_a + i_b).
	constant ALU_ADD    : alu_op_t := "00000";
	-- Deslocamento lógico à esquerda (SLL / SLLI).
	constant ALU_SLL    : alu_op_t := "00001";
	-- OU exclusivo bit a bit (i_a xor i_b).
	constant ALU_XOR    : alu_op_t := "00100";
	-- Deslocamento lógico à direita (SRL / SRLI).
	constant ALU_SRL    : alu_op_t := "00101";
	-- OU inclusivo bit a bit (i_a or i_b).
	constant ALU_OR     : alu_op_t := "00110";
	-- E lógico bit a bit (i_a and i_b).
	constant ALU_AND    : alu_op_t := "00111";
	-- Subtração aritmética (i_a - i_b).
	constant ALU_SUB    : alu_op_t := "01000";
	-- Comparação menor-que com sinal (SLT / SLTI).
	constant ALU_SLT    : alu_op_t := "01010";
	-- Comparação menor-que sem sinal (SLTU / SLTIU).
	constant ALU_SLTU   : alu_op_t := "01011";
	-- Deslocamento aritmético à direita com preservação de sinal (SRA / SRAI).
	constant ALU_SRA    : alu_op_t := "01101";
	-- Cálculo de endereço-alvo de salto indireto com bit menos significativo zerado (JALR).
	constant ALU_JALR   : alu_op_t := "10000";
	-- Carrega o imediato de B (LUI): soma com o operando A forçado a zero.
	constant ALU_LUI    : alu_op_t := "10001";
	-- Comparação de igualdade para desvio condicional (BEQ).
	constant ALU_BEQ    : alu_op_t := "11000";
	-- Comparação de diferença para desvio condicional (BNE).
	constant ALU_BNE    : alu_op_t := "11001";
	-- Comparação menor-que com sinal para desvio condicional (BLT).
	constant ALU_BLT    : alu_op_t := "11100";
	-- Comparação maior-ou-igual com sinal para desvio condicional (BGE).
	constant ALU_BGE    : alu_op_t := "11101";
	-- Comparação menor-que sem sinal para desvio condicional (BLTU).
	constant ALU_BLTU   : alu_op_t := "11110";
	-- Comparação maior-ou-igual sem sinal para desvio condicional (BGEU).
	constant ALU_BGEU   : alu_op_t := "11111";

	-- Posição, em alu_sel_t, da seleção da soma ou subtração (também JALR e LUI).
	constant ALU_SEL_SUM : natural := 0;
	-- Posição, em alu_sel_t, da seleção do deslocamento à esquerda.
	constant ALU_SEL_SLL : natural := 1;
	-- Posição, em alu_sel_t, da seleção de menor-que com sinal.
	constant ALU_SEL_SLT : natural := 2;
	-- Posição, em alu_sel_t, da seleção de menor-que sem sinal.
	constant ALU_SEL_SLTU : natural := 3;
	-- Posição, em alu_sel_t, da seleção do OU exclusivo.
	constant ALU_SEL_XOR : natural := 4;
	-- Posição, em alu_sel_t, da seleção do deslocamento à direita (lógico ou aritmético).
	constant ALU_SEL_SHR : natural := 5;
	-- Posição, em alu_sel_t, da seleção do OU.
	constant ALU_SEL_OR  : natural := 6;
	-- Posição, em alu_sel_t, da seleção do E.
	constant ALU_SEL_AND : natural := 7;

	-- Decodifica o código de operação na seleção one-hot do resultado de dados: JALR e LUI somam, os desvios
	-- não selecionam nada (o resultado de dados é zero) e as demais operações seguem o funct3 em op(2 downto 0).
	function alu_result_select(op : alu_op_t) return alu_sel_t;

end package alu_consts;

package body alu_consts is

	function alu_result_select(op : alu_op_t) return alu_sel_t is
		-- Seleção one-hot do resultado, inicialmente sem nenhum resultado selecionado.
		variable sel : alu_sel_t := (others => '0');
	begin
		if op(ALU_BIT_CLASS) = '1' then
			if op(ALU_BIT_INV) = '0' then
				sel(ALU_SEL_SUM) := '1';
			end if;
		else
			case op(2 downto 0) is
				when "000"  => sel(ALU_SEL_SUM)  := '1';
				when "001"  => sel(ALU_SEL_SLL)  := '1';
				when "010"  => sel(ALU_SEL_SLT)  := '1';
				when "011"  => sel(ALU_SEL_SLTU) := '1';
				when "100"  => sel(ALU_SEL_XOR)  := '1';
				when "101"  => sel(ALU_SEL_SHR)  := '1';
				when "110"  => sel(ALU_SEL_OR)   := '1';
				when others => sel(ALU_SEL_AND)  := '1';
			end case;
		end if;
		return sel;
	end function;

end package body alu_consts;
