-- =============================================================================
-- fencei_unit.vhd
-- Zifencei: a instrucao FENCE.I (opcode 0001111, funct3 = 001) em EX
-- (docs/contracts/01, 1.7).
--
-- Quando a instrucao e' valida e o pipeline anda (run), a unidade:
--   1. com HAS_DCACHE, pede o flush da cache de dados (flush_req, um pulso) e
--      segura a instrucao em EX (busy) ate' o fim dele (dc_done): uma cache
--      write-back pode ter o store de codigo ainda sujo;
--   2. sobe take por um ciclo: o core invalida a cache de instrucoes, esvazia
--      IF/ID e ID/EX e manda o PC para a instrucao seguinte.
-- Sem cache de dados, todo store anterior ja' chegou a' memoria nesse ciclo: o
-- estagio MEM so' deixa o pipeline andar quando o acesso terminou.
--
-- run e' o "pipeline anda" sem contar o proprio busy desta unidade (senao o busy
-- seguraria a si mesmo). FENCE comum (funct3 = 000) nao e' desta unidade: continua
-- um NOP.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity fencei_unit is
  generic (
    HAS_DCACHE : boolean := false
  );
  port (
    clk      : in  std_logic;
    reset    : in  std_logic;

    ex_valid : in  std_logic;
    run      : in  std_logic;
    opcode   : in  std_logic_vector(6 downto 0);
    funct3   : in  std_logic_vector(2 downto 0);

    -- cache de dados: dc_done e' o pulso de fim do flush
    dc_done  : in  std_logic := '0';
    flush_req : out std_logic;
    busy     : out std_logic;
    take     : out std_logic
  );
end entity fencei_unit;

architecture rtl of fencei_unit is
  signal is_fencei : std_logic;
  signal waiting   : std_logic := '0';
begin

  is_fencei <= '1' when ex_valid = '1' and opcode = "0001111" and funct3 = "001" else '0';

  gen_dc : if HAS_DCACHE generate
    -- o pedido sai no ciclo em que a instrucao chega a EX com o pipeline andando
    flush_req <= '1' when is_fencei = '1' and run = '1' and waiting = '0' else '0';
    busy      <= '1' when (is_fencei = '1' and run = '1' and waiting = '0')
                       or (waiting = '1' and dc_done = '0')
                 else '0';
    take      <= '1' when waiting = '1' and dc_done = '1' and is_fencei = '1' else '0';

    process (clk)
    begin
      if rising_edge(clk) then
        if reset = '1' then
          waiting <= '0';
        elsif is_fencei = '1' and run = '1' and waiting = '0' then
          waiting <= '1';
        elsif waiting = '1' and dc_done = '1' then
          waiting <= '0';
        end if;
      end if;
    end process;
  else generate
    flush_req <= '0';
    busy      <= '0';
    take      <= '1' when is_fencei = '1' and run = '1' else '0';
  end generate gen_dc;

end architecture rtl;
