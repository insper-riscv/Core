-- =============================================================================
-- Multiplexador de injeção de bolha (NOP) do pipeline RV32IM de 5 estágios
--
-- Posicionado entre a unidade de controle (control_unit) e o registrador de
-- pipeline ID/EX (reg_ID_EX).
-- Quando i_sel = '1', força nível lógico '0' nos sinais de controle que causam
-- escrita em estado arquitetural (banco de registradores e memória de dados)
-- ou que poderiam disparar detecções falsas de hazard nos estágios seguintes.
--
-- Quando i_sel = '0': saídas reproduzem as entradas (operação normal).
-- Quando i_sel = '1': saídas zeradas (NOP sem efeito colateral).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity bubble_mux is

	port (
		-- Seletor de bolha ('1' injeta NOP zerando os controles, '0' mantém as entradas).
		i_sel    : in  std_logic;
		-- Habilitação de escrita no banco de registradores vinda da unidade de controle.
		i_we_reg : in  std_logic;
		-- Habilitação de escrita na memória de dados vinda da unidade de controle.
		i_we_ram : in  std_logic;
		-- Habilitação de leitura da memória de dados vinda da unidade de controle.
		i_re_ram : in  std_logic;
		-- Habilitação geral de acesso à memória de dados vinda da unidade de controle.
		i_en_ram : in  std_logic;
		-- Habilitação de escrita no banco de registradores propagada ao estágio ID/EX.
		o_we_reg : out std_logic;
		-- Habilitação de escrita na memória de dados propagada ao estágio ID/EX.
		o_we_ram : out std_logic;
		-- Habilitação de leitura da memória de dados propagada ao estágio ID/EX.
		o_re_ram : out std_logic;
		-- Habilitação geral de acesso à memória de dados propagada ao estágio ID/EX.
		o_en_ram : out std_logic
	);

end entity bubble_mux;

architecture rtl of bubble_mux is
begin

	o_we_reg <= i_we_reg when i_sel = '0' else '0';
	o_we_ram <= i_we_ram when i_sel = '0' else '0';
	o_re_ram <= i_re_ram when i_sel = '0' else '0';
	o_en_ram <= i_en_ram when i_sel = '0' else '0';

end architecture rtl;
