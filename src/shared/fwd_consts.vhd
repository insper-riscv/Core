-- =============================================================================
-- Constantes dos seletores de adiantamento (forwarding) de operandos
--
-- Códigos de 2 bits produzidos pela forwarding_unit no estágio ID, registrados em
-- ID/EX e consumidos pelos muxes de operandos do estágio EX, que escolhem de onde
-- vem o valor de rs1 e rs2.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package fwd_consts is

    -- Seletor de fonte do operando adiantado (2 bits).
    subtype fwd_sel_t is std_logic_vector(1 downto 0);

    -- Sem conflito de dados: vale o valor lido no estágio ID.
    constant FWD_NONE  : fwd_sel_t := "00";
    -- Adiantamento do estágio MEM/WB (instrução duas posições à frente).
    constant FWD_MEMWB : fwd_sel_t := "01";
    -- Adiantamento do estágio EX/MEM (instrução imediatamente anterior).
    constant FWD_EXMEM : fwd_sel_t := "10";
    -- Adiantamento do estágio WB2 (instrução três posições à frente).
    constant FWD_WB2   : fwd_sel_t := "11";

    -- Cópias do seletor registrado de cada operando. Cada cópia comanda uma fatia do multiplexador de operando,
    -- o que reparte a carga do seletor.
    constant FWD_COPIES : positive := 4;

    -- Seletores das cópias de um operando lado a lado, a cópia i nos bits (2i + 1 downto 2i).
    subtype fwd_sel_bus_t is std_logic_vector((2 * FWD_COPIES) - 1 downto 0);

    -- Casamentos de um operando com as três instruções à frente, um bit por fonte de adiantamento.
    subtype fwd_match_t is std_logic_vector(2 downto 0);

    -- Posição, em fwd_match_t, do casamento com a instrução que estará em EX/MEM quando o operando for usado.
    constant FWD_MATCH_EXMEM : natural := 0;
    -- Posição, em fwd_match_t, do casamento com a instrução que estará em MEM/WB quando o operando for usado.
    constant FWD_MATCH_MEMWB : natural := 1;
    -- Posição, em fwd_match_t, do casamento com a instrução que estará em WB2 quando o operando for usado.
    constant FWD_MATCH_WB2   : natural := 2;

    -- Repete o seletor sel em copies cópias lado a lado, a cópia i nos bits (2i + 1 downto 2i).
    function replicate (sel : fwd_sel_t; copies : positive) return std_logic_vector;

end package fwd_consts;

package body fwd_consts is

    function replicate (sel : fwd_sel_t; copies : positive) return std_logic_vector is

        -- Cópias do seletor lado a lado.
        variable bus_v : std_logic_vector((2 * copies) - 1 downto 0);

    begin

        for i in 0 to copies - 1 loop
            bus_v((2 * i) + 1 downto 2 * i) := sel;
        end loop;

        return bus_v;

    end function replicate;

end package body fwd_consts;
