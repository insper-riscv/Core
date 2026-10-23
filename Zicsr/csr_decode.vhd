-- =============================================================================
-- csr_decode.vhd
-- Decodificacao da extensao Zicsr (docs/contracts/01).
--
-- Reivindica a classe SYSTEM (opcode 1110011). Com funct3 diferente de 000 e 100
-- sao os acessos a CSR (CSRRW, CSRRS, CSRRC e as versoes com imediato): sobem
-- isCsr e weReg. ECALL, EBREAK, MRET, WFI (funct3 = 000) e o funct3 reservado 100
-- sobem so' useImmI, para que o campo instruction[31:20] chegue a EX; quem os
-- executa ou os rejeita e' a unidade de traps.
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
  signal system : std_logic;
  signal claims : std_logic;
begin

  system <= '1' when instruction(6 downto 0) = "1110011" else '0';

  claims <= '1' when system = '1'
                 and instruction(14 downto 12) /= "000"
                 and instruction(14 downto 12) /= "100"
            else '0';

  isCsr   <= claims;
  weReg   <= claims;
  useImmI <= system;

end architecture rtl;
