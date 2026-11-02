-- =============================================================================
-- Extensor de leitura de memória de dados (loads RV32I)
--
-- Seleciona o subcampo (byte, meia-palavra ou palavra completa) da palavra de
-- 32 bits lida da memória de acordo com os 2 bits menos significativos do
-- endereço efetivo (i_byte_offset) e aplica extensão de sinal ou extensão por
-- zero conforme a operação selecionada em i_op (EXT_RAM_LW, EXT_RAM_LH,
-- EXT_RAM_LHU, EXT_RAM_LB, EXT_RAM_LBU).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.ext_ram_consts.all;
use work.byte_mask_consts.all;

entity extender_ram is
	port (
		-- Palavra bruta de 32 bits lida da memória de dados.
		i_data        : in  word_t;
		-- Seletor do modo de extensão de leitura (EXT_RAM_LW, EXT_RAM_LH, EXT_RAM_LHU, EXT_RAM_LB, EXT_RAM_LBU).
		i_op          : in  ext_ram_op_t;
		-- Deslocamento de byte dentro da palavra (bits [1:0] do endereço efetivo calculado).
		i_byte_offset : in  std_logic_vector(1 downto 0);
		-- Dado final de 32 bits alinhado e estendido para escrita no banco de registradores.
		o_data        : out word_t
	);
end entity extender_ram;

architecture rtl of extender_ram is
	-- Meia-palavra (16 bits) selecionada pelo bit 1 do endereço efetivo.
	signal selected_half : std_logic_vector(15 downto 0);
	-- Byte (8 bits) selecionado pelos bits [1:0] do endereço efetivo.
	signal selected_byte : std_logic_vector(7 downto 0);
begin

	-- Seleção da meia-palavra pelo offset do endereço (0: bytes 0 e 1; 1: bytes 1 e 2; 2: bytes 2 e 3).
	with i_byte_offset select
		selected_half <=
			i_data(15 downto 0)  when BYTE_OFFSET_0,
			i_data(23 downto 8)  when BYTE_OFFSET_1,
			i_data(31 downto 16) when others;

	-- Seleção do byte correspondente ao deslocamento i_byte_offset.
	with i_byte_offset select
		selected_byte <=
			i_data(7 downto 0)   when BYTE_OFFSET_0,
			i_data(15 downto 8)  when BYTE_OFFSET_1,
			i_data(23 downto 16) when BYTE_OFFSET_2,
			i_data(31 downto 24) when others;

	-- Extensão de sinal ou zero conforme o tipo de instrução de load.
	with i_op select
		o_data <=
			i_data                                              when EXT_RAM_LW,
			(31 downto 16 => selected_half(15)) & selected_half when EXT_RAM_LH,
			(31 downto 16 => '0')               & selected_half when EXT_RAM_LHU,
			(31 downto 8  => selected_byte(7))  & selected_byte when EXT_RAM_LB,
			(31 downto 8  => '0')               & selected_byte when EXT_RAM_LBU,
			(others => '0')                                     when others;

end architecture rtl;
