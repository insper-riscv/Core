-- =============================================================================
-- Banco de registradores discreto do pipeline RV32IM
--
-- Baseado no Apêndice C (Register Files) de Patterson & Hennessy.
-- Implementa 2^addr_width registradores de data_width bits com duas portas de
-- leitura combinacionais (i_rs1 -> o_rs1, i_rs2 -> o_rs2) e uma porta de
-- escrita síncrona (i_rd, i_d, i_enable).
--
-- Características:
--   - Registrador zero (x0 / endereço 0) fixado constantemente em zero.
--   - Demais registradores instanciados discretamente via generic_register
--     com habilitação decodificada por onehot_decoder.
--   - Leitura das portas rs1 e rs2 realizada por árvores de multiplexadores
--     (mux_tree).
--   - Bypass interno (write-through) via mux_2x1 quando há leitura e escrita
--     simultânea no mesmo registrador (exceto x0), garantindo que o estágio ID
--     observe o dado recém-escrito pelo estágio WB no mesmo ciclo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.utils_pkg.all;

entity reg_file is
	generic (
		-- Largura dos dados (em bits).
		data_width : natural := 32;
		-- Largura do endereço dos registradores (2^5 = 32 posições).
		addr_width : natural := 5
	);
	port (
		-- Endereço do primeiro registrador de leitura (rs1).
		i_rs1    : in  std_logic_vector((addr_width-1) downto 0);
		-- Endereço do segundo registrador de leitura (rs2).
		i_rs2    : in  std_logic_vector((addr_width-1) downto 0);
		-- Endereço do registrador de destino da escrita (rd).
		i_rd     : in  std_logic_vector((addr_width-1) downto 0);
		-- Dado de entrada para escrita no registrador rd.
		i_d      : in  std_logic_vector((data_width-1) downto 0);
		-- Dado lido do registrador endereçado por i_rs1.
		o_rs1    : out std_logic_vector((data_width-1) downto 0);
		-- Dado lido do registrador endereçado por i_rs2.
		o_rs2    : out std_logic_vector((data_width-1) downto 0);
		-- Habilita a escrita no registrador i_rd na borda de subida do clock.
		i_enable : in  std_logic;
		-- Sinal de clock.
		i_clk    : in  std_logic;
		-- Sinal de reset assíncrono (zera os registradores quando '1').
		i_rst    : in  std_logic := '0'
	);
end entity reg_file;

architecture rtl of reg_file is

	-- Endereço constante do registrador zero (x0).
	constant Z_REG : std_logic_vector((addr_width-1) downto 0) := (others => '0');
	-- Valor constante zero armazenado no registrador x0.
	constant Z_D   : std_logic_vector((data_width-1) downto 0) := (others => '0');

	-- Vetor one-hot que indica qual registrador está selecionado para escrita.
	signal decoded_rd  : std_logic_vector(((2**addr_width)-1) downto 0);
	-- Habilitação de escrita de cada registrador: i_enable combinado com a seleção one-hot de i_rd.
	signal reg_enable  : std_logic_vector(((2**addr_width)-1) downto 0);

	-- Matriz com as saídas atuais de todos os registradores (0 a 2^addr_width - 1).
	signal stored_d    : word_array_t(((2**addr_width)-1) downto 0)(data_width-1 downto 0);

	-- Dado selecionado da matriz de registradores para a porta rs1 (antes do bypass).
	signal rs1_d       : std_logic_vector((data_width-1) downto 0);
	-- Dado selecionado da matriz de registradores para a porta rs2 (antes do bypass).
	signal rs2_d       : std_logic_vector((data_width-1) downto 0);

	-- Seleção do bypass da porta rs1: '1' quando há escrita em i_rd igual a i_rs1 e o registrador não é x0.
	signal rs1_bypass_sel : std_logic;
	-- Seleção do bypass da porta rs2: '1' quando há escrita em i_rd igual a i_rs2 e o registrador não é x0.
	signal rs2_bypass_sel : std_logic;

begin

	-- Decodifica o registrador a ser escrito.
	u_write_decoder : entity work.onehot_decoder
		generic map (
			num_inputs => addr_width
		)
		port map (
			i_d => i_rd,
			o_d => decoded_rd
		);

	-- Constante do R0.
	stored_d(0) <= Z_D;
	reg_enable(0) <= '0';

	-- Registradores, a partir de 1 porque o x0 é constante.
	gen_regs : for i in 1 to ((2**addr_width)-1) generate
		reg_enable(i) <= i_enable and decoded_rd(i);

		u_reg : entity work.generic_register
			generic map (
				data_width => data_width
			)
			port map (
				i_d      => i_d,
				o_d      => stored_d(i),
				i_enable => reg_enable(i),
				i_clk    => i_clk,
				i_rst    => i_rst
			);
	end generate gen_regs;

	-- Seletores de dados das portas de leitura.
	u_d_mux_rs1 : entity work.mux_tree
		generic map (
			data_width     => data_width,
			selector_width => addr_width
		)
		port map (
			i_array => stored_d,
			i_sel   => i_rs1,
			o_d     => rs1_d
		);

	u_d_mux_rs2 : entity work.mux_tree
		generic map (
			data_width     => data_width,
			selector_width => addr_width
		)
		port map (
			i_array => stored_d,
			i_sel   => i_rs2,
			o_d     => rs2_d
		);

	-- Bypass para quando há escrita e leitura no mesmo registrador.
	rs1_bypass_sel <= i_enable and equals(i_rs1, i_rd) and not_equals(i_rs1, Z_REG);
	rs2_bypass_sel <= i_enable and equals(i_rs2, i_rd) and not_equals(i_rs2, Z_REG);

	u_rs1_bypass : entity work.mux_2x1
		generic map (
			data_width => data_width
		)
		port map (
			i_d0  => rs1_d,
			i_d1  => i_d,
			i_sel => rs1_bypass_sel,
			o_d   => o_rs1
		);

	u_rs2_bypass : entity work.mux_2x1
		generic map (
			data_width => data_width
		)
		port map (
			i_d0  => rs2_d,
			i_d1  => i_d,
			i_sel => rs2_bypass_sel,
			o_d   => o_rs2
		);

end architecture rtl;
