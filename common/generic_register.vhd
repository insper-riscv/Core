-- =============================================================================
-- Registrador paralelo parametrizável com habilitação e reset assíncrono
--
-- Armazena um vetor de dados de largura configurável (data_width) na borda
-- de subida de i_clk quando i_enable = '1'.
--
-- Quando i_rst = '1' (assíncrono): zera imediatamente a saída o_d.
-- Quando i_rst = '0' e borda de subida de i_clk:
--   - i_enable = '1': o_d recebe i_d
--   - i_enable = '0': o_d mantém o valor armazenado
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity generic_register is

	generic (
		-- Largura do registrador (em bits).
		data_width : natural := 8
	);

	port (
		-- Dado de entrada a ser registrado na borda de subida do clock.
		i_d      : in  std_logic_vector((data_width-1) downto 0);
		-- Dado armazenado no registrador.
		o_d      : out std_logic_vector((data_width-1) downto 0) := (others => '0');
		-- Habilita a atualização do registrador quando '1'.
		i_enable : in  std_logic;
		-- Sinal de clock.
		i_clk    : in  std_logic;
		-- Sinal de reset assíncrono ativo em '1'.
		i_rst    : in  std_logic
	);

end entity;

architecture rtl of generic_register is
begin
    process(i_rst, i_clk)
    begin
        -- O sinal de reset assíncrono possui a maior prioridade.
        if (i_rst = '1') then
            o_d <= (others => '0');
        else
            -- Na borda de subida do clock, atualiza o registrador se habilitado.
            if (rising_edge(i_clk)) then
                if (i_enable = '1') then
                    o_d <= i_d;
                end if;
            end if;
        end if;
    end process;
end architecture;
