-- =============================================================================
-- m_decode.vhd
-- Decodificacao da extensao M (docs/contracts/01, 1.1).
--
-- Reivindica as instrucoes R-type com funct7 = "0000001" (MUL, MULH, MULHSU,
-- MULHU, DIV, DIVU, REM, REMU; a operacao vem de funct3, decodificada no
-- multdiv por decoderM) e gera os sinais de controle que a extensao precisa.
--
-- Regra do contrato: uma extensao so' dirige os campos que sobem; o resto do
-- pacote de controle fica em zero, e o pipeline combina os pacotes por OU.
-- Para o M, sobem weReg (escreve rd), selPCRS1 (operando A = rs1) e isMulDiv
-- (o resultado vem da unidade M, nao da ALU).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity m_decode is
  port (
    instruction : in  std_logic_vector(31 downto 0);

    -- '1' se a instrucao e' da extensao M
    isMulDiv    : out std_logic;
    weReg       : out std_logic;
    selPCRS1    : out std_logic
  );
end entity m_decode;

architecture rtl of m_decode is
  signal claims : std_logic;
begin

  claims <= '1' when instruction(6 downto 0)   = "0110011"
                 and instruction(31 downto 25) = "0000001"
            else '0';

  isMulDiv <= claims;
  weReg    <= claims;
  selPCRS1 <= claims;

end architecture rtl;
