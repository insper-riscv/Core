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
--   - Zihpm: cinco faixas de 32 endereços, em que o índice N (de 3 a 31) é o endereço de
--     base da faixa mais N, a saber mhpmeventN (0x320), mhpmcounterN (0xB00), mhpmcounterNh
--     (0xB80), hpmcounterN (0xC00) e hpmcounterNh (0xC80). Os 7 bits altos do endereço
--     identificam a faixa e os 5 bits baixos o índice.
--   - Sscofpmf: mhpmeventNh em 0x720 + N (N de 3 a 31), a metade alta do seletor de evento com os bits OF e MINH.
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

  -- Faixa (bits [11:5] do endereço) de mcountinhibit, no índice 0, e dos seletores de evento mhpmeventN (0x320 a 0x33F).
  constant RANGE_MHPMEVENT    : std_logic_vector(6 downto 0) := ADDR_MCOUNTINHIBIT(11 downto 5);
  -- Faixa (bits [11:5] do endereço) das metades altas dos seletores de evento da Sscofpmf, mhpmeventNh (0x720 a 0x73F).
  constant RANGE_MHPMEVENTH   : std_logic_vector(6 downto 0) := "0111001";
  -- Faixa (bits [11:5] do endereço) das metades baixas dos contadores de máquina (0xB00 a 0xB1F).
  constant RANGE_MHPMCOUNTER  : std_logic_vector(6 downto 0) := ADDR_MCYCLE(11 downto 5);
  -- Faixa (bits [11:5] do endereço) das metades altas dos contadores de máquina (0xB80 a 0xB9F).
  constant RANGE_MHPMCOUNTERH : std_logic_vector(6 downto 0) := ADDR_MCYCLEH(11 downto 5);
  -- Faixa (bits [11:5] do endereço) dos espelhos somente leitura das metades baixas (0xC00 a 0xC1F).
  constant RANGE_HPMCOUNTER   : std_logic_vector(6 downto 0) := ADDR_CYCLE(11 downto 5);
  -- Faixa (bits [11:5] do endereço) dos espelhos somente leitura das metades altas (0xC80 a 0xC9F).
  constant RANGE_HPMCOUNTERH  : std_logic_vector(6 downto 0) := ADDR_CYCLEH(11 downto 5);
  -- Índice (bits [4:0] do endereço) do primeiro contador de eventos, mhpmcounter3.
  constant HPM_FIRST_INDEX    : natural := 3;
  -- Índice do último contador de eventos, mhpmcounter31.
  constant HPM_LAST_INDEX     : natural := 31;
  -- Quantidade de contadores de eventos que a especificação define (índices 3 a 31).
  constant HPM_MAX_COUNTERS   : natural := HPM_LAST_INDEX - HPM_FIRST_INDEX + 1;

end package csr_addr_consts;
