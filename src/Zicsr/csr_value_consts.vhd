-- =============================================================================
-- Constantes de valor e de codificação do banco de CSRs
--
-- Valores fixos do registrador misa e códigos usados pelo csr_file para decidir
-- a operação de escrita (bits [1:0] do funct3 das instruções CSRR*) e o CSR
-- somente leitura (bits [11:10] do endereço).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

package csr_value_consts is

	-- Valor do registrador misa com MXL = 1 (RV32) e a extensão I; a extensão M soma o bit 12.
	constant MISA_BASE   : word_t := x"40000100";
	-- Valor do registrador misa com MXL = 1 (RV32) e as extensões I e M.
	constant MISA_WITH_M : word_t := x"40001100";

	-- Operação de um acesso a CSR, bits [1:0] do funct3 (2 bits).
	subtype csr_op_t is std_logic_vector(1 downto 0);

	-- Escrita atômica do valor (CSRRW e CSRRWI).
	constant CSR_OP_WRITE : csr_op_t := "01";
	-- Set de bits atômico (CSRRS e CSRRSI).
	constant CSR_OP_SET   : csr_op_t := "10";

	-- Bits [11:10] do endereço que marcam o CSR como somente leitura.
	constant CSR_ADDR_READ_ONLY : std_logic_vector(1 downto 0) := "11";

end package csr_value_consts;
