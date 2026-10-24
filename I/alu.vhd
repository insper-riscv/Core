-- =============================================================================
-- Unidade Lógica e Aritmética (ULA) parametrizável do pipeline RV32IM
--
-- Executa combinacionalmente as operações aritméticas, lógicas, deslocamentos,
-- comparações (SLT/SLTU), cálculo de endereço-alvo de JALR e avaliação de
-- condição de desvio (BEQ, BNE, BLT, BGE, BLTU, BGEU) selecionadas por i_op.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.utils_pkg.all;
use work.alu_consts.all;

entity alu is

	generic (
		-- Largura dos operandos e do resultado (em bits).
		data_width : natural := 32
	);

	port (
		-- Código de operação de 5 bits da ULA (definido em alu_consts).
		i_op     : in  alu_op_t;
		-- Operando A (primeiro operando da operação).
		i_a      : in  std_logic_vector((data_width-1) downto 0);
		-- Operando B (segundo operando da operação).
		i_b      : in  std_logic_vector((data_width-1) downto 0);
		-- Resultado da operação selecionada.
		o_d      : out std_logic_vector((data_width-1) downto 0);
		-- Indicador de condição de desvio satisfeita ('1' quando o branch é tomado).
		o_branch : out std_logic
	);

end entity alu;

architecture rtl of alu is

	-- Quantidade de bits necessários para representar o deslocamento máximo (log2(data_width)).
	constant SHAMT_WIDTH : natural := log2_ceil(data_width);

begin

	process(i_op, i_a, i_b)
		-- Soma temporária utilizada para limpar o bit menos significativo na operação JALR.
		variable v_sum : std_logic_vector((data_width-1) downto 0);
	begin
		-- Valores padrão para evitar inferência de latches.
		o_d      <= (others => '0');
		o_branch <= '0';

		if (i_op = ALU_PASS_B) then
			o_d <= i_b;

		elsif (i_op = ALU_ADD) then
			o_d <= std_logic_vector(unsigned(i_a) + unsigned(i_b));

		elsif (i_op = ALU_XOR) then
			o_d <= i_a xor i_b;

		elsif (i_op = ALU_OR) then
			o_d <= i_a or i_b;

		elsif (i_op = ALU_AND) then
			o_d <= i_a and i_b;

		elsif (i_op = ALU_SLL) then
			o_d <= std_logic_vector(shift_left(unsigned(i_a), to_integer(unsigned(i_b(SHAMT_WIDTH-1 downto 0)))));

		elsif (i_op = ALU_SRL) then
			o_d <= std_logic_vector(shift_right(unsigned(i_a), to_integer(unsigned(i_b(SHAMT_WIDTH-1 downto 0)))));

		elsif (i_op = ALU_SRA) then
			o_d <= std_logic_vector(shift_right(signed(i_a), to_integer(unsigned(i_b(SHAMT_WIDTH-1 downto 0)))));

		elsif (i_op = ALU_SUB) then
			o_d <= std_logic_vector(unsigned(i_a) - unsigned(i_b));

		elsif (i_op = ALU_SLT) then
			if signed(i_a) < signed(i_b) then
				o_d <= (data_width-1 downto 1 => '0') & '1';
			else
				o_d <= (others => '0');
			end if;

		elsif (i_op = ALU_SLTU) then
			if unsigned(i_a) < unsigned(i_b) then
				o_d <= (data_width-1 downto 1 => '0') & '1';
			else
				o_d <= (others => '0');
			end if;

		elsif (i_op = ALU_JALR) then
			v_sum := std_logic_vector(unsigned(i_a) + unsigned(i_b));
			o_d   <= v_sum((data_width-1) downto 1) & '0';

		elsif (i_op = ALU_BEQ) then
			if i_a = i_b then
				o_branch <= '1';
			end if;

		elsif (i_op = ALU_BNE) then
			if i_a /= i_b then
				o_branch <= '1';
			end if;

		elsif (i_op = ALU_BLT) then
			if signed(i_a) < signed(i_b) then
				o_branch <= '1';
			end if;

		elsif (i_op = ALU_BGE) then
			if signed(i_a) >= signed(i_b) then
				o_branch <= '1';
			end if;

		elsif (i_op = ALU_BLTU) then
			if unsigned(i_a) < unsigned(i_b) then
				o_branch <= '1';
			end if;

		elsif (i_op = ALU_BGEU) then
			if unsigned(i_a) >= unsigned(i_b) then
				o_branch <= '1';
			end if;

		else
			null;
		end if;
	end process;

end architecture rtl;
