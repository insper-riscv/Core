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
    -- In Altera devices, register signals have a set priority.
    -- The HDL design should reflect this priority.
    process(i_rst, i_clk)
    begin
        -- The asynchronous reset signal has the highest priority
        if (i_rst = '1') then
            o_d <= (others => '0');    -- Código reconfigurável.
        else
            -- At a clock edge, if asynchronous signals have not taken priority,
            -- respond to the appropriate synchronous signal.
            -- Check for synchronous reset, then synchronous load.
            -- If none of these takes precedence, update the register output
            -- to be the register input.
            if (rising_edge(i_clk)) then
                if (i_enable = '1') then
                        o_d <= i_d;
                end if;
            end if;
        end if;
    end process;
end architecture;
