-- =============================================================================
-- trap_unit.vhd
-- Deteccao de excecoes sincronas do modo maquina e de MRET, na instrucao de EX
-- (docs/contracts/01, 1.6).
--
-- Puramente combinacional. A instrucao de EX gera no maximo uma excecao:
--
--   causa  excecao                              mtval
--     0    alvo de desvio ou salto desalinhado  o alvo
--     2    instrucao ilegal (SYSTEM nao suportada, CSR inexistente ou escrita em
--          CSR somente leitura)                 0
--     3    ebreak                               0
--     4    load desalinhado                     endereco efetivo
--     6    store desalinhado                    endereco efetivo
--    11    ecall                                0
--
-- take e mret_take so' sobem no ciclo em que a instrucao e' valida e o pipeline
-- anda (run): uma instrucao parada em EX nao repete o efeito. O WFI e' um NOP.
-- O PC (mepc) e' o da instrucao em EX.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity trap_unit is
  port (
    ex_valid : in  std_logic;
    run      : in  std_logic;

    opcode   : in  std_logic_vector(6 downto 0);
    funct3   : in  std_logic_vector(2 downto 0);
    rd_idx   : in  std_logic_vector(4 downto 0);
    rs1_idx  : in  std_logic_vector(4 downto 0);
    imm12    : in  std_logic_vector(11 downto 0);  -- instruction[31:20]

    -- endereco efetivo de load e store (resultado da ALU)
    ea           : in  std_logic_vector(31 downto 0);
    -- desvio ou salto tomado e o alvo (desvio condicional, JAL ou JALR)
    cf_taken     : in  std_logic;
    cf_target    : in  std_logic_vector(31 downto 0);
    csr_illegal  : in  std_logic;

    take       : out std_logic;
    mret_take  : out std_logic;
    cause      : out std_logic_vector(31 downto 0);
    tval       : out std_logic_vector(31 downto 0)
  );
end entity trap_unit;

architecture rtl of trap_unit is

  constant OP_SYSTEM : std_logic_vector(6 downto 0) := "1110011";
  constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
  constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";

  signal is_system : std_logic;
  signal is_csr    : std_logic;
  signal no_regs   : std_logic;  -- rd = x0, rs1 = x0 e funct3 = 000
  signal is_ecall  : std_logic;
  signal is_ebreak : std_logic;
  signal is_mret   : std_logic;
  signal is_wfi    : std_logic;

  signal sys_illegal : std_logic;
  signal ld_misal    : std_logic;
  signal st_misal    : std_logic;
  signal cf_misal    : std_logic;

  signal exc : std_logic;

begin

  is_system <= '1' when opcode = OP_SYSTEM else '0';
  is_csr    <= '1' when is_system = '1' and funct3 /= "000" and funct3 /= "100" else '0';
  no_regs   <= '1' when funct3 = "000" and rd_idx = "00000" and rs1_idx = "00000" else '0';

  is_ecall  <= '1' when is_system = '1' and no_regs = '1' and imm12 = x"000" else '0';
  is_ebreak <= '1' when is_system = '1' and no_regs = '1' and imm12 = x"001" else '0';
  is_mret   <= '1' when is_system = '1' and no_regs = '1' and imm12 = x"302" else '0';
  is_wfi    <= '1' when is_system = '1' and no_regs = '1' and imm12 = x"105" else '0';

  sys_illegal <= '1' when is_system = '1' and is_csr = '0'
                       and is_ecall = '0' and is_ebreak = '0'
                       and is_mret = '0' and is_wfi = '0'
                 else '0';

  ld_misal <= '1' when opcode = OP_LOAD and
                       ((funct3(1 downto 0) = "10" and ea(1 downto 0) /= "00") or
                        (funct3(1 downto 0) = "01" and ea(0) = '1'))
              else '0';

  st_misal <= '1' when opcode = OP_STORE and
                       ((funct3 = "010" and ea(1 downto 0) /= "00") or
                        (funct3 = "001" and ea(0) = '1'))
              else '0';

  cf_misal <= '1' when cf_taken = '1' and cf_target(1 downto 0) /= "00" else '0';

  exc <= cf_misal or sys_illegal or (is_csr and csr_illegal) or is_ebreak
         or ld_misal or st_misal or is_ecall;

  take      <= exc and ex_valid and run;
  mret_take <= is_mret and ex_valid and run;

  cause <= x"00000000" when cf_misal = '1' else
           x"00000002" when sys_illegal = '1' or (is_csr = '1' and csr_illegal = '1') else
           x"00000003" when is_ebreak = '1' else
           x"00000004" when ld_misal = '1' else
           x"00000006" when st_misal = '1' else
           x"0000000B";

  tval <= cf_target when cf_misal = '1' else
          ea        when ld_misal = '1' or st_misal = '1' else
          x"00000000";

end architecture rtl;
