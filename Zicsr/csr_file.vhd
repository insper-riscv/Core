-- =============================================================================
-- csr_file.vhd
-- Banco de CSRs do modo maquina e execucao das instrucoes Zicsr.
--
-- O valor antigo do CSR e' combinacional (rdata) e segue o caminho do resultado
-- da ALU. A escrita acontece na borda de clock em que commit = '1', isto e,
-- no ciclo em que a instrucao de EX e' valida e o pipeline anda; uma
-- instrucao parada em EX nao repete o efeito. Duas instrucoes CSR seguidas
-- enxergam o valor novo, pois o registrador muda na mesma borda em que a
-- primeira sai de EX.
--
-- op = funct3 da instrucao (001 RW, 010 RS, 011 RC; o bit 2 so' diz que o
-- operando e' imediato e quem o escolhe e' o pipeline, que entrega o valor em
-- wdata). src_zero = '1' quando o campo rs1 (ou zimm) e' zero: RS e RC nao
-- escrevem nesse caso.
--
-- Tomada de trap (trap_take): mepc, mcause e mtval recebem os valores de entrada,
-- MPIE recebe MIE e MIE vai a zero. MRET (mret_take): MIE recebe MPIE e MPIE
-- vai a 1. Ambos tem prioridade sobre uma escrita CSR da mesma borda (que nao
-- existe: o trap e' da propria instrucao de EX).
--
-- CSRs: mstatus, misa, mie, mtvec, mscratch, mepc, mcause, mtval, mip,
-- mstatush, mvendorid, marchid, mimpid, mhartid, mconfigptr. Um endereco que
-- nao esta na lista, ou uma escrita efetiva em CSR somente leitura (bits 11 e
-- 10 do endereco iguais a 1), levanta illegal.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity csr_file is
  port (
    clk      : in  std_logic;
    reset    : in  std_logic;

    commit   : in  std_logic;
    addr     : in  std_logic_vector(11 downto 0);
    op       : in  std_logic_vector(2 downto 0);
    wdata    : in  std_logic_vector(31 downto 0);
    src_zero : in  std_logic;

    rdata    : out std_logic_vector(31 downto 0);
    illegal  : out std_logic;

    -- Trap e MRET (docs/contracts/01, 1.6). take e mret_take valem no ciclo em
    -- que a instrucao de EX e' valida e o pipeline anda, como commit.
    trap_take  : in  std_logic := '0';
    trap_cause : in  std_logic_vector(31 downto 0) := (others => '0');
    trap_pc    : in  std_logic_vector(31 downto 0) := (others => '0');
    trap_tval  : in  std_logic_vector(31 downto 0) := (others => '0');
    mret_take  : in  std_logic := '0';

    -- Destinos de redirecionamento do PC.
    mtvec_o  : out std_logic_vector(31 downto 0);
    mepc_o   : out std_logic_vector(31 downto 0)
  );
end entity csr_file;

architecture rtl of csr_file is

  constant ADDR_MSTATUS    : std_logic_vector(11 downto 0) := x"300";
  constant ADDR_MISA       : std_logic_vector(11 downto 0) := x"301";
  constant ADDR_MIE        : std_logic_vector(11 downto 0) := x"304";
  constant ADDR_MTVEC      : std_logic_vector(11 downto 0) := x"305";
  constant ADDR_MSTATUSH   : std_logic_vector(11 downto 0) := x"310";
  constant ADDR_MSCRATCH   : std_logic_vector(11 downto 0) := x"340";
  constant ADDR_MEPC       : std_logic_vector(11 downto 0) := x"341";
  constant ADDR_MCAUSE     : std_logic_vector(11 downto 0) := x"342";
  constant ADDR_MTVAL      : std_logic_vector(11 downto 0) := x"343";
  constant ADDR_MIP        : std_logic_vector(11 downto 0) := x"344";
  constant ADDR_MVENDORID  : std_logic_vector(11 downto 0) := x"F11";
  constant ADDR_MARCHID    : std_logic_vector(11 downto 0) := x"F12";
  constant ADDR_MIMPID     : std_logic_vector(11 downto 0) := x"F13";
  constant ADDR_MHARTID    : std_logic_vector(11 downto 0) := x"F14";
  constant ADDR_MCONFIGPTR : std_logic_vector(11 downto 0) := x"F15";

  -- RV32 (MXL = 1), extensoes I e M.
  constant MISA_VALUE : std_logic_vector(31 downto 0) := x"40001100";

  -- mstatus: so' MIE (bit 3) e MPIE (bit 7) sao escreviveis; MPP (bits 12 e 11)
  -- le 11 porque o core so' tem o modo maquina.
  signal mstatus_mie  : std_logic := '0';
  signal mstatus_mpie : std_logic := '0';
  signal mtvec        : std_logic_vector(31 downto 0) := (others => '0');
  signal mscratch     : std_logic_vector(31 downto 0) := (others => '0');
  signal mepc         : std_logic_vector(31 downto 0) := (others => '0');
  signal mcause       : std_logic_vector(31 downto 0) := (others => '0');
  signal mtval        : std_logic_vector(31 downto 0) := (others => '0');

  signal mstatus_value : std_logic_vector(31 downto 0);
  signal old_value     : std_logic_vector(31 downto 0);
  signal new_value     : std_logic_vector(31 downto 0);
  signal known         : std_logic;
  signal read_only     : std_logic;
  signal write_effect  : std_logic;

begin

  mstatus_value <= (12 => '1', 11 => '1', 7 => mstatus_mpie, 3 => mstatus_mie, others => '0');

  process(addr, mstatus_value, mtvec, mscratch, mepc, mcause, mtval)
  begin
    old_value <= (others => '0');
    known     <= '1';
    case addr is
      when ADDR_MSTATUS    => old_value <= mstatus_value;
      when ADDR_MISA       => old_value <= MISA_VALUE;
      when ADDR_MTVEC      => old_value <= mtvec;
      when ADDR_MSCRATCH   => old_value <= mscratch;
      when ADDR_MEPC       => old_value <= mepc;
      when ADDR_MCAUSE     => old_value <= mcause;
      when ADDR_MTVAL      => old_value <= mtval;
      when ADDR_MIE | ADDR_MIP | ADDR_MSTATUSH |
           ADDR_MVENDORID | ADDR_MARCHID | ADDR_MIMPID |
           ADDR_MHARTID | ADDR_MCONFIGPTR => null;
      when others          => known <= '0';
    end case;
  end process;

  rdata  <= old_value;
  mtvec_o <= mtvec;
  mepc_o  <= mepc;

  with op(1 downto 0) select
    new_value <= wdata                       when "01",
                 old_value or wdata          when "10",
                 old_value and (not wdata)   when others;

  write_effect <= '1' when op(1 downto 0) = "01" or src_zero = '0' else '0';
  read_only    <= '1' when addr(11 downto 10) = "11" else '0';
  illegal      <= (not known) or (write_effect and read_only);

  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        mstatus_mie  <= '0';
        mstatus_mpie <= '0';
        mtvec        <= (others => '0');
        mscratch     <= (others => '0');
        mepc         <= (others => '0');
        mcause       <= (others => '0');
        mtval        <= (others => '0');
      elsif trap_take = '1' then
        mepc         <= trap_pc(31 downto 2) & "00";
        mcause       <= trap_cause;
        mtval        <= trap_tval;
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= '0';
      elsif mret_take = '1' then
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= '1';
      elsif commit = '1' and write_effect = '1' and known = '1' and read_only = '0' then
        case addr is
          when ADDR_MSTATUS =>
            mstatus_mie  <= new_value(3);
            mstatus_mpie <= new_value(7);
          when ADDR_MTVEC    => mtvec    <= new_value(31 downto 2) & "00";
          when ADDR_MSCRATCH => mscratch <= new_value;
          when ADDR_MEPC     => mepc     <= new_value(31 downto 2) & "00";
          when ADDR_MCAUSE   => mcause   <= new_value;
          when ADDR_MTVAL    => mtval    <= new_value;
          when others        => null;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
