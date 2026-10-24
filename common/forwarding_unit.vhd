-- =============================================================================
-- Unidade de adiantamento de dados (forwarding / bypass) do pipeline RV32IM
--
-- Detecta dependências de dados RAW (Read After Write) entre a instrução em
-- execução no estágio EX e as instruções anteriores nos estágios MEM e WB,
-- selecionando a fonte mais recente para os operandos rs1 e rs2 da ULA.
--
-- Codificação de o_fwd_rs1 / o_fwd_rs2:
--   "00" = sem adiantamento -> utiliza o valor lido do reg_ID_EX (banco de registradores)
--   "10" = adiantamento EX/MEM -> utiliza o resultado calculado no estágio MEM
--   "01" = adiantamento MEM/WB -> utiliza o dado de write-back do estágio WB
--
-- Prioridade: EX/MEM > MEM/WB > ID/EX
--   Quando duas instruções consecutivas escrevem no mesmo registrador rd, o
--   resultado mais recente (EX/MEM) prevalece sobre o mais antigo (MEM/WB).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;

entity forwarding_unit is

	port (
		-- Endereço do registrador fonte rs1 da instrução no estágio EX (vindo do reg_ID_EX).
		i_ex_rs1       : in  reg_t;
		-- Endereço do registrador fonte rs2 da instrução no estágio EX (vindo do reg_ID_EX).
		i_ex_rs2       : in  reg_t;
		-- Endereço do registrador destino rd da instrução no estágio MEM (vindo do reg_EX_MEM).
		i_exmem_rd     : in  reg_t;
		-- Habilitação de escrita no banco de registradores da instrução no estágio MEM.
		i_exmem_we_reg : in  std_logic;
		-- Endereço do registrador destino rd da instrução no estágio WB (vindo do reg_MEM_WB).
		i_memwb_rd     : in  reg_t;
		-- Habilitação de escrita no banco de registradores da instrução no estágio WB.
		i_memwb_we_reg : in  std_logic;
		-- Seletor do multiplexador de adiantamento para o operando rs1 no estágio EX.
		o_fwd_rs1      : out std_logic_vector(1 downto 0);
		-- Seletor do multiplexador de adiantamento para o operando rs2 no estágio EX.
		o_fwd_rs2      : out std_logic_vector(1 downto 0)
	);

end entity forwarding_unit;

architecture rtl of forwarding_unit is

	-- Endereço constante do registrador zero (x0), que nunca sofre adiantamento.
	constant REG_ZERO : reg_t := (others => '0');

begin

	-- ===========================================================================
	-- Adiantamento para o operando rs1
	-- ===========================================================================
	process(i_ex_rs1, i_exmem_rd, i_exmem_we_reg, i_memwb_rd, i_memwb_we_reg)
	begin
		if    i_exmem_we_reg = '1'
		  and i_exmem_rd /= REG_ZERO
		  and i_exmem_rd  = i_ex_rs1
		then
			-- Hazard EX/MEM: instrução imediatamente anterior escreve em rs1.
			o_fwd_rs1 <= "10";

		elsif i_memwb_we_reg = '1'
		  and i_memwb_rd /= REG_ZERO
		  and i_memwb_rd  = i_ex_rs1
		then
			-- Hazard MEM/WB: instrução duas posições à frente escreve em rs1.
			o_fwd_rs1 <= "01";

		else
			-- Sem conflito de dados: valor lido no estágio ID é válido.
			o_fwd_rs1 <= "00";
		end if;
	end process;

	-- ===========================================================================
	-- Adiantamento para o operando rs2
	-- ===========================================================================
	process(i_ex_rs2, i_exmem_rd, i_exmem_we_reg, i_memwb_rd, i_memwb_we_reg)
	begin
		if    i_exmem_we_reg = '1'
		  and i_exmem_rd /= REG_ZERO
		  and i_exmem_rd  = i_ex_rs2
		then
			o_fwd_rs2 <= "10";

		elsif i_memwb_we_reg = '1'
		  and i_memwb_rd /= REG_ZERO
		  and i_memwb_rd  = i_ex_rs2
		then
			o_fwd_rs2 <= "01";

		else
			o_fwd_rs2 <= "00";
		end if;
	end process;

end architecture rtl;
