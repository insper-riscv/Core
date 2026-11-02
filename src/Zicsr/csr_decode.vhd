-- =============================================================================
-- Decodificador de instruções da extensão Zicsr e classe SYSTEM
--
-- Reivindica no estágio ID as instruções da classe SYSTEM (opcode = OPCODE_SYSTEM):
--   - Acessos a CSRs (funct3 diferente de FUNCT3_PRIV e FUNCT3_SYSTEM_RESERVED: CSRRW, CSRRS, CSRRC,
--     CSRRWI, CSRRSI, CSRRCI): ativam o_is_csr = '1', o_we_reg = '1' e o_use_imm_i = '1'.
--   - Instruções privilegiadas (ECALL, EBREAK, MRET, WFI, funct3 = FUNCT3_PRIV) ou
--     subfunção reservada (FUNCT3_SYSTEM_RESERVED): ativam apenas o_use_imm_i = '1' para encaminhar
--     o campo instr[31:20] até a trap_unit no estágio EX.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;

entity csr_decode is
	port (
		-- Instrução de 32 bits presente no estágio ID.
		i_instr     : in  word_t;
		-- Indica que a instrução realiza leitura/escrita em registrador CSR.
		o_is_csr    : out std_logic;
		-- Habilita a escrita do valor antigo do CSR no registrador destino rd.
		o_we_reg    : out std_logic;
		-- Força o extensor de imediato a extrair o campo I-type (instr[31:20]).
		o_use_imm_i : out std_logic
	);
end entity csr_decode;

architecture rtl of csr_decode is
	-- Alias para o campo opcode (bits [6:0]) da instrução.
	alias opcode : opcode_t is i_instr(6 downto 0);
	-- Alias para o campo funct3 (bits [14:12]) da instrução.
	alias funct3 : funct3_t is i_instr(14 downto 12);

	-- Indica que a instrução pertence à classe SYSTEM (opcode 1110011).
	signal is_system : std_logic;
	-- Indica que a instrução SYSTEM é uma operação válida de acesso a CSR.
	signal is_csr_op : std_logic;
begin

	is_system <= '1' when opcode = OPCODE_SYSTEM else '0';

	is_csr_op <= '1' when (is_system = '1' and funct3 /= FUNCT3_PRIV and funct3 /= FUNCT3_SYSTEM_RESERVED) else '0';

	o_is_csr    <= is_csr_op;
	o_we_reg    <= is_csr_op;
	o_use_imm_i <= is_system;

end architecture rtl;
