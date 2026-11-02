-- =============================================================================
-- Unidade Lógica e Aritmética (ULA) parametrizável do pipeline RV32IM
--
-- Executa combinacionalmente as operações aritméticas, lógicas, deslocamentos,
-- comparações (SLT/SLTU), cálculo de endereço-alvo de JALR, carga de imediato
-- (LUI) e avaliação de condição de desvio (BEQ, BNE, BLT, BGE, BLTU, BGEU)
-- selecionadas por i_op (ver alu_consts).
--
-- Um único somador-subtrator atende soma, subtração, SLT, SLTU, JALR, LUI e as
-- quatro comparações de desvio: com o bit de inversão de i_op em '1', o operando
-- B entra invertido com carry-in 1, e o sinal e o carry-out da diferença dão
-- "menor que" com e sem sinal. A igualdade (BEQ/BNE) usa um comparador próprio,
-- que não espera a cadeia de carry.
--
-- Os deslocadores (um à esquerda, um à direita com preenchimento de sinal
-- selecionável) são escritos em estágios de multiplexadores 4 para 1, cada um
-- cobrindo dois bits da quantidade de deslocamento, o que cabe numa LUT de 6
-- entradas por estágio.
--
-- O resultado de dados sai de um único E-OU com a seleção one-hot i_res_sel,
-- decodificada no estágio ID (alu_result_select) e registrada em ID/EX. As
-- operações que só dependem de lógica bit a bit (XOR, OR, AND e os bits de SLT)
-- formam um grupo rápido que não espera o somador nem os deslocadores. Nos
-- desvios a seleção é zero, então o resultado de dados é zero e só o_branch vale.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;
use work.utils_pkg.all;
use work.alu_consts.all;
use work.funct3_consts.all;

entity alu is

	generic (
		-- Largura dos operandos e do resultado (em bits).
		data_width : natural := 32
	);

	port (
		-- Código da operação (alu_op_t, ver alu_consts).
		i_op      : in  alu_op_t;
		-- Seleção one-hot do resultado de dados (alu_result_select de i_op).
		i_res_sel : in  alu_sel_t;
		-- Operando A (rs1 ou PC).
		i_a       : in  std_logic_vector((data_width-1) downto 0);
		-- Operando B (rs2 ou imediato).
		i_b       : in  std_logic_vector((data_width-1) downto 0);
		-- Resultado de dados da operação.
		o_d       : out std_logic_vector((data_width-1) downto 0);
		-- Condição de desvio avaliada ('1' = desvio tomado); '0' fora dos desvios.
		o_branch  : out std_logic
	);

end entity alu;

architecture rtl of alu is

	-- Número de bits do campo de quantidade de deslocamento.
	constant SHAMT_WIDTH : natural := log2_ceil(data_width);
	-- Número de estágios de deslocamento, cada um cobrindo dois bits da quantidade.
	constant SHIFT_STAGES : natural := (SHAMT_WIDTH + 1) / 2;

	-- Vetor de estágios intermediários do deslocamento.
	type stage_array_t is array (0 to SHIFT_STAGES) of std_logic_vector((data_width-1) downto 0);

	-- Desloca x à direita de n posições, preenchendo com fill à esquerda.
	function shift_right_fill(x : std_logic_vector; n : natural; fill : std_logic) return std_logic_vector is
		-- Vetor resultado do deslocamento à direita, com a largura de x.
		variable r : std_logic_vector(x'length - 1 downto 0);
	begin
		for i in r'range loop
			if i + n < x'length then
				r(i) := x(i + n);
			else
				r(i) := fill;
			end if;
		end loop;
		return r;
	end function;

	-- Desloca x à esquerda de n posições, preenchendo com zero à direita.
	function shift_left_zero(x : std_logic_vector; n : natural) return std_logic_vector is
		-- Vetor resultado do deslocamento à esquerda, com a largura de x.
		variable r : std_logic_vector(x'length - 1 downto 0);
	begin
		for i in r'range loop
			if i >= n then
				r(i) := x(i - n);
			else
				r(i) := '0';
			end if;
		end loop;
		return r;
	end function;

	-- Bit de classe de controle da operação (JALR, LUI e desvios).
	signal op_class    : std_logic;
	-- Bit de inversão de B com carry-in 1 (subtração, comparação, deslocamento aritmético).
	signal op_inv      : std_logic;
	-- Seleção da condição de desvio conforme o funct3 do desvio.
	signal op_sel      : std_logic_vector(2 downto 0);
	-- A operação é um desvio condicional.
	signal is_branch   : std_logic;
	-- A operação é JALR.
	signal is_jalr     : std_logic;
	-- A operação é LUI.
	signal is_lui      : std_logic;

	-- Operando A efetivo: zero em LUI, i_a nas demais operações.
	signal a_eff       : std_logic_vector((data_width-1) downto 0);
	-- Operando B, invertido quando op_inv = '1'.
	signal b_xor       : std_logic_vector((data_width-1) downto 0);
	-- Carry-in do somador (igual a op_inv).
	signal carry_in    : unsigned(0 downto 0);
	-- Soma de a_eff e b_xor com carry-in, com um bit a mais para o carry-out.
	signal sum_ext     : unsigned(data_width downto 0);
	-- Resultado da soma ou subtração, com o bit 0 zerado em JALR.
	signal sum         : std_logic_vector((data_width-1) downto 0);

	-- Menor-que com sinal de i_a e i_b, válido com op_inv = '1'.
	signal lt_signed   : std_logic;
	-- Menor-que sem sinal de i_a e i_b, válido com op_inv = '1'.
	signal lt_unsigned : std_logic;
	-- Igualdade de i_a e i_b.
	signal equal       : std_logic;

	-- Bit de preenchimento do deslocamento à direita (sinal em SRA, zero em SRL).
	signal shift_fill  : std_logic;
	-- Estágios do deslocamento à esquerda.
	signal shl_stage   : stage_array_t;
	-- Estágios do deslocamento à direita.
	signal shr_stage   : stage_array_t;

	-- Grupo rápido do resultado: operações bit a bit e menor-que, que não esperam somador nem deslocadores.
	signal fast_out    : std_logic_vector((data_width-1) downto 0);
	-- Grupo lento do resultado: soma e deslocamentos.
	signal slow_out    : std_logic_vector((data_width-1) downto 0);

begin

	op_class  <= i_op(ALU_BIT_CLASS);
	op_inv    <= i_op(ALU_BIT_INV);
	op_sel    <= i_op(2 downto 0);
	
	is_branch <= op_class and op_inv;
	is_jalr   <= op_class and (not op_inv) and (not i_op(0));
	is_lui    <= op_class and (not op_inv) and i_op(0);

	-- Somador-subtrator compartilhado.
	a_eff     <= (others => '0') when is_lui = '1' else i_a;
	b_xor     <= i_b xor (data_width-1 downto 0 => op_inv);
	carry_in  <= (0 => op_inv);
	sum_ext   <= ('0' & unsigned(a_eff)) + ('0' & unsigned(b_xor)) + carry_in;
	sum       <= std_logic_vector(sum_ext((data_width-1) downto 1)) & (sum_ext(0) and not is_jalr);

	lt_unsigned <= not sum_ext(data_width);
	lt_signed   <= i_a(data_width-1) when (i_a(data_width-1) xor i_b(data_width-1)) = '1'
	               else sum_ext(data_width-1);
	equal       <= '1' when i_a = i_b else '0';

	-- Deslocadores em estágios de 4 para 1, dois bits da quantidade por estágio.
	shift_fill   <= op_inv and i_a(data_width-1);
	shl_stage(0) <= i_a;
	shr_stage(0) <= i_a;

	gen_shift : for p in 0 to SHIFT_STAGES - 1 generate
		gen_quad : if 2 * p + 1 < SHAMT_WIDTH generate
			with i_b(2 * p + 1 downto 2 * p) select
				shl_stage(p + 1) <=
					shl_stage(p)                                  when SHIFT_DIGIT_0,
					shift_left_zero(shl_stage(p), 1 * 4 ** p)     when SHIFT_DIGIT_1,
					shift_left_zero(shl_stage(p), 2 * 4 ** p)     when SHIFT_DIGIT_2,
					shift_left_zero(shl_stage(p), 3 * 4 ** p)     when others;
			with i_b(2 * p + 1 downto 2 * p) select
				shr_stage(p + 1) <=
					shr_stage(p)                                          when SHIFT_DIGIT_0,
					shift_right_fill(shr_stage(p), 1 * 4 ** p, shift_fill) when SHIFT_DIGIT_1,
					shift_right_fill(shr_stage(p), 2 * 4 ** p, shift_fill) when SHIFT_DIGIT_2,
					shift_right_fill(shr_stage(p), 3 * 4 ** p, shift_fill) when others;
		end generate gen_quad;
		gen_single : if 2 * p + 1 >= SHAMT_WIDTH generate
			shl_stage(p + 1) <= shift_left_zero(shl_stage(p), 4 ** p) when i_b(2 * p) = '1' else shl_stage(p);
			shr_stage(p + 1) <= shift_right_fill(shr_stage(p), 4 ** p, shift_fill) when i_b(2 * p) = '1' else shr_stage(p);
		end generate gen_single;
	end generate gen_shift;

	-- Resultado de dados: E-OU com a seleção one-hot, em dois grupos.
	fast_out <= ((data_width-1 downto 0 => i_res_sel(ALU_SEL_XOR)) and (i_a xor i_b)) or
	            ((data_width-1 downto 0 => i_res_sel(ALU_SEL_OR))  and (i_a or i_b))  or
	            ((data_width-1 downto 0 => i_res_sel(ALU_SEL_AND)) and (i_a and i_b)) or
	            ((data_width-1 downto 1 => '0') & (i_res_sel(ALU_SEL_SLT)  and lt_signed)) or
	            ((data_width-1 downto 1 => '0') & (i_res_sel(ALU_SEL_SLTU) and lt_unsigned));

	slow_out <= ((data_width-1 downto 0 => i_res_sel(ALU_SEL_SUM)) and sum) or
	            ((data_width-1 downto 0 => i_res_sel(ALU_SEL_SLL)) and shl_stage(SHIFT_STAGES)) or
	            ((data_width-1 downto 0 => i_res_sel(ALU_SEL_SHR)) and shr_stage(SHIFT_STAGES));

	o_d <= fast_out or slow_out;

	with op_sel select
		o_branch <=
			is_branch and equal                       when FUNCT3_BEQ,
			is_branch and not equal                   when FUNCT3_BNE,
			is_branch and lt_signed                   when FUNCT3_BLT,
			is_branch and not lt_signed               when FUNCT3_BGE,
			is_branch and lt_unsigned                 when FUNCT3_BLTU,
			is_branch and not lt_unsigned             when FUNCT3_BGEU,
			'0'                                       when others;

end architecture rtl;
