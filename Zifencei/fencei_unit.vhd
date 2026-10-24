-- =============================================================================
-- fencei_unit.vhd
-- Zifencei: a instrucao FENCE.I (opcode 0001111, funct3 = 001) em EX
-- (docs/contracts/01, 1.7).
--
-- Combinacional. Quando a instrucao e' valida e o pipeline anda (run), take sobe
-- por um ciclo: o core invalida a cache de instrucoes, esvazia IF/ID e ID/EX e
-- manda o PC para a instrucao seguinte. Todo store anterior ja' chegou a' memoria
-- nesse ciclo: o estagio MEM so' deixa o pipeline andar quando o acesso terminou.
-- FENCE comum (funct3 = 000) nao e' desta unidade: continua um NOP.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity fencei_unit is
  port (
    ex_valid : in  std_logic;
    run      : in  std_logic;
    opcode   : in  std_logic_vector(6 downto 0);
    funct3   : in  std_logic_vector(2 downto 0);
    take     : out std_logic
  );
end entity fencei_unit;

architecture rtl of fencei_unit is
begin

  take <= '1' when ex_valid = '1' and run = '1' and opcode = "0001111" and funct3 = "001"
          else '0';

end architecture rtl;
