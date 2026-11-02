-- =============================================================================
-- Registrador de estágio IF/ID do pipeline RV32IM de 5 estágios
--
-- Captura, na borda de subida de i_clk, o endereço da instrução (PC), PC + 4 e
-- a palavra de instrução buscada no estágio IF, disponibilizando-os ao estágio
-- ID no ciclo seguinte.
--
-- Prioridade dos controles síncronos:
--   1. i_rst = '1' ou i_flush = '1' -> limpa os registradores e marca o pacote
--                                      como bolha inválida (o_valid = '0').
--   2. i_en = '1'                   -> captura as entradas normalmente.
--   3. i_en = '0'                   -> mantém o estado atual (stall).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

entity reg_if_id is

	port (
		-- Sinal de clock.
		i_clk   : in  std_logic;
		-- Sinal de reset síncrono ativo em '1'.
		i_rst   : in  std_logic;
		-- Habilita a captura do estágio IF/ID ('1' = avança, '0' = congela em stall).
		i_en    : in  std_logic;
		-- Descarta a instrução buscada injetando bolha ('1' = flush por desvio/trap).
		i_flush : in  std_logic;
		-- Indica que a instrução entregue pelo barramento de busca é válida.
		i_valid : in  std_logic := '1';
		-- Endereço PC da instrução buscada no estágio IF.
		i_pc    : in  word_t;
		-- Valor de PC + 4 calculado no estágio IF.
		i_pc4   : in  word_t;
		-- Palavra de instrução de 32 bits vinda da memória de instruções.
		i_inst  : in  word_t;
		-- Indica ao estágio ID se o pacote armazenado contém uma instrução válida.
		o_valid : out std_logic;
		-- Endereço PC registrado para o estágio ID.
		o_pc    : out word_t;
		-- Valor de PC + 4 registrado para o estágio ID.
		o_pc4   : out word_t;
		-- Palavra de instrução registrada para o estágio ID.
		o_inst  : out word_t
	);

end entity reg_if_id;

architecture rtl of reg_if_id is

	-- Bit de validade armazenado no registrador de estágio.
	signal r_valid : std_logic := '0';
	-- Endereço PC armazenado no registrador de estágio.
	signal r_pc    : word_t    := (others => '0');
	-- Valor de PC + 4 armazenado no registrador de estágio.
	signal r_pc4   : word_t    := (others => '0');
	-- Instrução de 32 bits armazenada no registrador de estágio.
	signal r_inst  : word_t    := (others => '0');

begin

	process(i_clk)
	begin
		if rising_edge(i_clk) then
			if i_rst = '1' or i_flush = '1' then
				r_valid <= '0';
				r_pc    <= (others => '0');
				r_pc4   <= (others => '0');
				r_inst  <= (others => '0');
			elsif i_en = '1' then
				r_valid <= i_valid;
				r_pc    <= i_pc;
				r_pc4   <= i_pc4;
				r_inst  <= i_inst;
			end if;
		end if;
	end process;

	o_valid <= r_valid;
	o_pc    <= r_pc;
	o_pc4   <= r_pc4;
	o_inst  <= r_inst;

end architecture rtl;
