-- =============================================================================
-- Endereços dos CSRs do Modo Máquina implementados pela extensão Zicsr
--
-- Cada constante é o campo csr (bits [31:20]) da instrução que acessa o CSR.
-- Os valores vêm do volume II da especificação do RISC-V (The RISC-V Instruction
-- Set Manual, Volume II: Privileged Architecture), nas tabelas de endereços dos
-- CSRs de nível máquina (Machine-Level CSRs):
--   - 0x300 a 0x344: configuração e tratamento de traps (mstatus a mip).
--   - 0xB00 a 0xB82: contadores de máquina da extensão Zicntr (mcycle, minstret e metades altas).
--   - 0xC00 a 0xC82: espelhos somente leitura dos contadores (cycle, time, instret e metades altas).
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
  -- Endereço do CSR mcountinhibit (inibe a soma de mcycle, minstret e dos contadores de eventos).
  constant ADDR_MCOUNTINHIBIT : std_logic_vector(11 downto 0) := x"320";
  -- Primeiro CSR de seleção de evento (mhpmevent3); o de índice N fica em 0x320 + N.
  constant ADDR_MHPMEVENT_BASE   : std_logic_vector(11 downto 0) := x"320";
  -- Primeiro contador de eventos de usuário na faixa de máquina (mhpmcounter0); o de índice N fica em 0xB00 + N.
  constant ADDR_MHPMCOUNTER_BASE : std_logic_vector(11 downto 0) := x"B00";
  -- Primeira metade alta de contador de eventos (mhpmcounter0h); o de índice N fica em 0xB80 + N.
  constant ADDR_MHPMCOUNTERH_BASE : std_logic_vector(11 downto 0) := x"B80";
  -- Primeiro espelho de leitura de contador de eventos (hpmcounter0); o de índice N fica em 0xC00 + N.
  constant ADDR_HPMCOUNTER_BASE  : std_logic_vector(11 downto 0) := x"C00";
  -- Primeiro espelho de leitura da metade alta (hpmcounter0h); o de índice N fica em 0xC80 + N.
  constant ADDR_HPMCOUNTERH_BASE : std_logic_vector(11 downto 0) := x"C80";
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
  -- Endereço do CSR mcycle (ciclos de clock do core, 32 bits baixos).
  constant ADDR_MCYCLE     : std_logic_vector(11 downto 0) := x"B00";
  -- Endereço do CSR minstret (instruções retiradas, 32 bits baixos).
  constant ADDR_MINSTRET   : std_logic_vector(11 downto 0) := x"B02";
  -- Endereço do CSR mcycleh (32 bits altos de mcycle).
  constant ADDR_MCYCLEH    : std_logic_vector(11 downto 0) := x"B80";
  -- Endereço do CSR minstreth (32 bits altos de minstret).
  constant ADDR_MINSTRETH  : std_logic_vector(11 downto 0) := x"B82";
  -- Endereço do CSR cycle (espelho somente leitura de mcycle).
  constant ADDR_CYCLE      : std_logic_vector(11 downto 0) := x"C00";
  -- Endereço do CSR time (contador de tempo da plataforma, 32 bits baixos).
  constant ADDR_TIME       : std_logic_vector(11 downto 0) := x"C01";
  -- Endereço do CSR instret (espelho somente leitura de minstret).
  constant ADDR_INSTRET    : std_logic_vector(11 downto 0) := x"C02";
  -- Endereço do CSR cycleh (espelho somente leitura de mcycleh).
  constant ADDR_CYCLEH     : std_logic_vector(11 downto 0) := x"C80";
  -- Endereço do CSR timeh (32 bits altos de time).
  constant ADDR_TIMEH      : std_logic_vector(11 downto 0) := x"C81";
  -- Endereço do CSR instreth (espelho somente leitura de minstreth).
  constant ADDR_INSTRETH   : std_logic_vector(11 downto 0) := x"C82";
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
