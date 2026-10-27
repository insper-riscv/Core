-- =============================================================================
-- Endereços dos CSRs do Modo Máquina implementados pela extensão Zicsr
--
-- Cada constante é o campo csr (bits [31:20]) da instrução que acessa o CSR.
-- Os valores vêm do volume II da especificação do RISC-V (The RISC-V Instruction
-- Set Manual, Volume II: Privileged Architecture), nas tabelas de endereços dos
-- CSRs de nível máquina (Machine-Level CSRs):
--   - 0x300 a 0x344: configuração e tratamento de traps (mstatus a mip).
--   - 0xF11 a 0xF15: identificação, somente leitura (mvendorid a mconfigptr).
-- Os bits [11:10] = "11" do endereço marcam o CSR como somente-leitura, regra
-- que o csr_file usa para rejeitar escritas efetivas.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package csr_addr_consts is

  -- Endereço do CSR mstatus (Machine Status Register).
  constant ADDR_MSTATUS    : std_logic_vector(11 downto 0) := x"300";
  -- Endereço do CSR misa (Machine ISA Register).
  constant ADDR_MISA       : std_logic_vector(11 downto 0) := x"301";
  -- Endereço do CSR mie (Machine Interrupt Enable Register).
  constant ADDR_MIE        : std_logic_vector(11 downto 0) := x"304";
  -- Endereço do CSR mtvec (Machine Trap-Vector Base-Address Register).
  constant ADDR_MTVEC      : std_logic_vector(11 downto 0) := x"305";
  -- Endereço do CSR mstatush (Machine Status Register Upper 32 bits).
  constant ADDR_MSTATUSH   : std_logic_vector(11 downto 0) := x"310";
  -- Endereço do CSR mscratch (Machine Scratch Register).
  constant ADDR_MSCRATCH   : std_logic_vector(11 downto 0) := x"340";
  -- Endereço do CSR mepc (Machine Exception Program Counter).
  constant ADDR_MEPC       : std_logic_vector(11 downto 0) := x"341";
  -- Endereço do CSR mcause (Machine Cause Register).
  constant ADDR_MCAUSE     : std_logic_vector(11 downto 0) := x"342";
  -- Endereço do CSR mtval (Machine Trap Value Register).
  constant ADDR_MTVAL      : std_logic_vector(11 downto 0) := x"343";
  -- Endereço do CSR mip (Machine Interrupt Pending Register).
  constant ADDR_MIP        : std_logic_vector(11 downto 0) := x"344";
  -- Endereço do CSR mvendorid (Machine Vendor ID Register).
  constant ADDR_MVENDORID  : std_logic_vector(11 downto 0) := x"F11";
  -- Endereço do CSR marchid (Machine Architecture ID Register).
  constant ADDR_MARCHID    : std_logic_vector(11 downto 0) := x"F12";
  -- Endereço do CSR mimpid (Machine Implementation ID Register).
  constant ADDR_MIMPID     : std_logic_vector(11 downto 0) := x"F13";
  -- Endereço do CSR mhartid (Hart ID Register).
  constant ADDR_MHARTID    : std_logic_vector(11 downto 0) := x"F14";
  -- Endereço do CSR mconfigptr (Machine Configuration Pointer Register).
  constant ADDR_MCONFIGPTR : std_logic_vector(11 downto 0) := x"F15";

end package csr_addr_consts;
