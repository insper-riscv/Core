-- =============================================================================
-- Constantes de valor e de codificação do banco de CSRs
--
-- Valores fixos do registrador misa e códigos usados pelo csr_file para decidir
-- a operação de escrita (bits [1:0] do funct3 das instruções CSRR*) e o CSR
-- somente leitura (bits [11:10] do endereço).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils_pkg.all;
use work.config_pkg.all;
use work.pipeline_types.all;

package csr_value_consts is

    -- Campo MXL do misa, nos dois bits mais altos da palavra: 1 para XLEN 32 e 2 para XLEN 64.
    constant MISA_MXL : word_t := std_logic_vector(shift_left(to_unsigned(pick(IS_64, 2, 1), XLEN), XLEN - 2));

    -- Valor do registrador misa com o MXL de XLEN e a extensão I; a extensão M soma o bit 12.
    constant MISA_BASE     : word_t := MISA_MXL or std_logic_vector(to_unsigned(256, XLEN));
    -- Valor do registrador misa com o MXL de XLEN e as extensões I e M.
    constant MISA_WITH_M   : word_t := MISA_MXL or std_logic_vector(to_unsigned(4352, XLEN));
    -- Valor do registrador misa com o MXL de XLEN e a base E (bit 4) no lugar da I; a extensão M soma o bit 12.
    constant MISA_E_BASE   : word_t := MISA_MXL or std_logic_vector(to_unsigned(16, XLEN));
    -- Valor do registrador misa com o MXL de XLEN, a base E (bit 4) e a extensão M.
    constant MISA_E_WITH_M : word_t := MISA_MXL or std_logic_vector(to_unsigned(4112, XLEN));

    -- Operação de um acesso a CSR, bits [1:0] do funct3 (2 bits).
    subtype csr_op_t is std_logic_vector(1 downto 0);

    -- Escrita atômica do valor (CSRRW e CSRRWI).
    constant CSR_OP_WRITE : csr_op_t := "01";
    -- Set de bits atômico (CSRRS e CSRRSI).
    constant CSR_OP_SET   : csr_op_t := "10";

    -- Bits [11:10] do endereço que marcam o CSR como somente leitura.
    constant CSR_ADDR_READ_ONLY : std_logic_vector(1 downto 0) := "11";

end package csr_value_consts;
