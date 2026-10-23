-- =============================================================================
-- csr_decode.vhd
-- Decodificacao da extensao Zicsr (docs/contracts/01).
--
-- Reivindica a classe SYSTEM (opcode 1110011) com funct3 /= 000: CSRRW, CSRRS,
-- CSRRC e as versoes com imediato. ECALL, EBREAK, MRET e WFI (funct3 = 000)
-- nao sao desta unidade.
--
-- Como em m_decode, a extensao so' dirige os campos que sobem: weReg (escreve
-- rd com o valor antigo do CSR) e useImmI (o endereco do CSR, instruction[31:20],
-- chega a EX pelo extensor de imediato do tipo I). O operando A nao e' usado:
-- o dado de escrita sai do rs1 com forwarding, ou do campo rs1 (zimm).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity csr_decode is
  port (
    instruction : in  std_logic_vector(31 downto 0);

    -- '1' se a instrucao e' um acesso a CSR
    isCsr       : out std_logic;
    weReg       : out std_logic;
    useImmI     : out std_logic
  );
end entity csr_decode;

architecture rtl of csr_decode is
  signal claims : std_logic;
begin

  claims <= '1' when instruction(6 downto 0)   = "1110011"
                 and instruction(14 downto 12) /= "000"
                 and instruction(14 downto 12) /= "100"
            else '0';

  isCsr   <= claims;
  weReg   <= claims;
  useImmI <= claims;

end architecture rtl;
