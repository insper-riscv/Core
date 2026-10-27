-- =============================================================================
-- Gerenciador de alinhamento e máscara de escrita em memória (stores RV32I)
--
-- Posiciona o dado do registrador de origem rs2 (i_rs2_data) nas lanes de byte
-- corretas da palavra de 32 bits (o_data) e gera a máscara de habilitação de
-- escrita por byte de 4 bits (o_byte_mask) de acordo com o opcode (i_opcode),
-- a largura da transferência (i_funct3: SB, SH, SW) e o deslocamento de byte do
-- endereço efetivo (i_byte_offset).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;

entity store_manager is
	port (
		-- Campo opcode (bits [6:0]) da instrução no estágio EX.
		i_opcode      : in  opcode_t;
		-- Campo funct3 (bits [14:12]) que define a largura do store (FUNCT3_SB, FUNCT3_SH, FUNCT3_SW).
		i_funct3      : in  funct3_t;
		-- Deslocamento de byte dentro da palavra (bits [1:0] do endereço efetivo calculado).
		i_byte_offset : in  std_logic_vector(1 downto 0);
		-- Valor de 32 bits do registrador rs2 a ser armazenado na memória.
		i_rs2_data    : in  word_t;
		-- Palavra de 32 bits com o dado posicionado nos bytes correspondentes ao endereço.
		o_data        : out word_t;
		-- Máscara de habilitação de escrita por byte (1 bit por byte da palavra de 32 bits).
		o_byte_mask   : out byte_mask_t
	);
end entity store_manager;

architecture rtl of store_manager is
	-- Indica que a instrução atual corresponde a uma operação de escrita em memória (STORE).
	signal is_store  : std_logic;
	-- Palavra alinhada para escrita de meia-palavra (SH).
	signal sh_data   : word_t;
	-- Máscara de bytes para escrita de meia-palavra (SH).
	signal sh_mask   : byte_mask_t;
	-- Palavra alinhada para escrita de byte (SB).
	signal sb_data   : word_t;
	-- Máscara de bytes para escrita de byte (SB).
	signal sb_mask   : byte_mask_t;
begin

	is_store <= '1' when i_opcode = OPCODE_STORE else '0';

	-- Alinhamento e máscara para Store Halfword (SH), com offset 0, 1 (bytes 1 e 2) ou 2.
	with i_byte_offset select
		sh_data <=
			X"0000" & i_rs2_data(15 downto 0)          when "00",
			X"00"   & i_rs2_data(15 downto 0) & X"00"  when "01",
			i_rs2_data(15 downto 0) & X"0000"          when others;

	with i_byte_offset select
		sh_mask <=
			"0011" when "00",
			"0110" when "01",
			"1100" when others;

	-- Alinhamento e máscara para Store Byte (SB).
	with i_byte_offset select
		sb_data <=
			X"000000" & i_rs2_data(7 downto 0)            when "00",
			X"0000"   & i_rs2_data(7 downto 0) & X"00"    when "01",
			X"00"     & i_rs2_data(7 downto 0) & X"0000"  when "10",
			i_rs2_data(7 downto 0)             & X"000000" when others;

	with i_byte_offset select
		sb_mask <=
			"0001" when "00",
			"0010" when "01",
			"0100" when "10",
			"1000" when others;

	-- Seleção final do dado e da máscara de acordo com i_funct3 quando is_store = '1'.
	o_data <= i_rs2_data      when (is_store = '1' and i_funct3 = FUNCT3_SW) else
	          sh_data         when (is_store = '1' and i_funct3 = FUNCT3_SH) else
	          sb_data         when (is_store = '1' and i_funct3 = FUNCT3_SB) else
	          (others => '0');

	o_byte_mask <= "1111"     when (is_store = '1' and i_funct3 = FUNCT3_SW) else
	               sh_mask    when (is_store = '1' and i_funct3 = FUNCT3_SH) else
	               sb_mask    when (is_store = '1' and i_funct3 = FUNCT3_SB) else
	               (others => '0');

end architecture rtl;
