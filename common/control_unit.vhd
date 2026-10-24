-- =============================================================================
-- Unidade de Controle principal do pipeline RV32IM de 5 estágios
--
-- Decodifica combinacionalmente a instrução de 32 bits (i_inst) vinda do
-- registrador de estágio IF/ID utilizando aliases para os campos opcode,
-- funct3 e funct7 e as constantes semânticas da arquitetura.
--
-- Instruções fora do conjunto base RV32I (como a extensão M com funct7 =
-- FUNCT7_MULDIV ou instruções CSR/Zifencei) produzem um NOP sem efeitos
-- colaterais nesta unidade, sendo reivindicadas pelos seus decodificadores
-- dedicados (m_decode, csr_decode, fencei_unit) no topo do pipeline.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use work.pipeline_types.all;
use work.opcode_consts.all;
use work.funct3_consts.all;
use work.funct7_consts.all;
use work.alu_consts.all;
use work.ext_imm_consts.all;
use work.ext_ram_consts.all;
use work.wb_sel_consts.all;

entity control_unit is

	port (
		-- Instrução completa de 32 bits vinda do registrador de pipeline IF/ID.
		i_inst        : in  word_t;
		-- Indica salto incondicional (JAL / JALR) para a lógica de desvio no estágio EX.
		o_sel_pc4_alu : out std_logic;
		-- Seletor do formato de imediato para o extensor de imediato (ext_imm_op_t).
		o_ext_imm_op  : out ext_imm_op_t;
		-- Seletor da fonte de escrita no estágio WB (ALU, PC+4, RAM ou CSR).
		o_wb_sel      : out wb_sel_t;
		-- Habilita a escrita no banco de registradores no estágio WB.
		o_we_reg      : out std_logic;
		-- Seletor do modo de extensão de leitura da memória de dados (LW, LH, LHU, LB, LBU).
		o_ext_ram_op  : out ext_ram_op_t;
		-- Seleciona o operando B da ULA ('0' = rs2, '1' = imediato estendido).
		o_sel_rs2_imm : out std_logic;
		-- Seleciona o operando A da ULA ('0' = PC, '1' = rs1).
		o_sel_pc_rs1  : out std_logic;
		-- Código de operação de 5 bits da ULA.
		o_alu_op      : out alu_op_t;
		-- Habilita a escrita na memória de dados no estágio MEM.
		o_we_ram      : out std_logic;
		-- Habilita a leitura da memória de dados no estágio MEM.
		o_re_ram      : out std_logic;
		-- Habilita o acesso à memória de dados no estágio MEM.
		o_en_ram      : out std_logic;
		-- Campo opcode extraído da instrução (bits [6:0]) para a HDU e estágios seguintes.
		o_opcode      : out opcode_t;
		-- Campo funct3 extraído da instrução (bits [14:12]) para multdiv e StoreManager.
		o_funct3      : out funct3_t
	);

end entity control_unit;

architecture rtl of control_unit is

	-- Campo opcode da instrução (bits [6:0]).
	alias opcode : opcode_t is i_inst(6 downto 0);
	-- Campo funct3 da instrução (bits [14:12]).
	alias funct3 : funct3_t is i_inst(14 downto 12);
	-- Campo funct7 da instrução (bits [31:25]).
	alias funct7 : funct7_t is i_inst(31 downto 25);

begin

	-- Repassa diretamente os campos extraídos por alias para as saídas do pipeline.
	o_opcode <= opcode;
	o_funct3 <= funct3;

	-- ===========================================================================
	-- Decodificação combinacional das instruções RV32I base
	-- ===========================================================================
	process(i_inst)
	begin
		-- Valores padrão seguros (NOP sem escrita em registrador nem acesso à memória).
		o_sel_pc4_alu <= '0';
		o_ext_imm_op  <= EXT_IMM_U;
		o_wb_sel      <= WB_SEL_ALU;
		o_we_reg      <= '0';
		o_ext_ram_op  <= EXT_RAM_LW;
		o_sel_rs2_imm <= '0';
		o_sel_pc_rs1  <= '0';
		o_alu_op      <= ALU_PASS_B;
		o_we_ram      <= '0';
		o_re_ram      <= '0';
		o_en_ram      <= '0';

		case opcode is

			-- -----------------------------------------------------------------------
			-- Instruções aritméticas/lógicas com imediato e shifts (I-type ALU)
			-- -----------------------------------------------------------------------
			when OPCODE_OP_IMM =>
				case funct3 is
					when FUNCT3_SLLI =>
						if funct7 = FUNCT7_SLLI then
							o_ext_imm_op  <= EXT_IMM_I_SHAMT;
							o_we_reg      <= '1';
							o_sel_rs2_imm <= '1';
							o_sel_pc_rs1  <= '1';
							o_alu_op      <= ALU_SLL;
						end if;

					when FUNCT3_SRLI_SRAI =>
						if funct7 = FUNCT7_SRLI then
							o_ext_imm_op  <= EXT_IMM_I_SHAMT;
							o_we_reg      <= '1';
							o_sel_rs2_imm <= '1';
							o_sel_pc_rs1  <= '1';
							o_alu_op      <= ALU_SRL;
						elsif funct7 = FUNCT7_SRAI then
							o_ext_imm_op  <= EXT_IMM_I_SHAMT;
							o_we_reg      <= '1';
							o_sel_rs2_imm <= '1';
							o_sel_pc_rs1  <= '1';
							o_alu_op      <= ALU_SRA;
						end if;

					when FUNCT3_ADDI =>
						o_ext_imm_op  <= EXT_IMM_I;
						o_we_reg      <= '1';
						o_sel_rs2_imm <= '1';
						o_sel_pc_rs1  <= '1';
						o_alu_op      <= ALU_ADD;

					when FUNCT3_XORI =>
						o_ext_imm_op  <= EXT_IMM_I;
						o_we_reg      <= '1';
						o_sel_rs2_imm <= '1';
						o_sel_pc_rs1  <= '1';
						o_alu_op      <= ALU_XOR;

					when FUNCT3_ORI =>
						o_ext_imm_op  <= EXT_IMM_I;
						o_we_reg      <= '1';
						o_sel_rs2_imm <= '1';
						o_sel_pc_rs1  <= '1';
						o_alu_op      <= ALU_OR;

					when FUNCT3_ANDI =>
						o_ext_imm_op  <= EXT_IMM_I;
						o_we_reg      <= '1';
						o_sel_rs2_imm <= '1';
						o_sel_pc_rs1  <= '1';
						o_alu_op      <= ALU_AND;

					when FUNCT3_SLTI =>
						o_ext_imm_op  <= EXT_IMM_I;
						o_we_reg      <= '1';
						o_sel_rs2_imm <= '1';
						o_sel_pc_rs1  <= '1';
						o_alu_op      <= ALU_SLT;

					when FUNCT3_SLTIU =>
						o_ext_imm_op  <= EXT_IMM_I;
						o_we_reg      <= '1';
						o_sel_rs2_imm <= '1';
						o_sel_pc_rs1  <= '1';
						o_alu_op      <= ALU_SLTU;

					when others =>
						null;
				end case;

			-- -----------------------------------------------------------------------
			-- Instruções registrador-registrador do RV32I base (R-type)
			-- -----------------------------------------------------------------------
			when OPCODE_OP =>
				if funct7 = FUNCT7_DEFAULT or funct7 = FUNCT7_ALT then
					o_we_reg     <= '1';
					o_sel_pc_rs1 <= '1';

					case funct3 is
						when FUNCT3_ADD_SUB =>
							if funct7 = FUNCT7_SUB then
								o_alu_op <= ALU_SUB;
							else
								o_alu_op <= ALU_ADD;
							end if;

						when FUNCT3_SLL  => o_alu_op <= ALU_SLL;
						when FUNCT3_SLT  => o_alu_op <= ALU_SLT;
						when FUNCT3_SLTU => o_alu_op <= ALU_SLTU;
						when FUNCT3_XOR  => o_alu_op <= ALU_XOR;

						when FUNCT3_SRL_SRA =>
							if funct7 = FUNCT7_SRA then
								o_alu_op <= ALU_SRA;
							else
								o_alu_op <= ALU_SRL;
							end if;

						when FUNCT3_OR   => o_alu_op <= ALU_OR;
						when FUNCT3_AND  => o_alu_op <= ALU_AND;
						when others      => null;
					end case;
				end if;

			-- -----------------------------------------------------------------------
			-- Desvios condicionais (B-type)
			-- -----------------------------------------------------------------------
			when OPCODE_BRANCH =>
				o_ext_imm_op <= EXT_IMM_B;
				o_sel_pc_rs1 <= '1';

				case funct3 is
					when FUNCT3_BEQ  => o_alu_op <= ALU_BEQ;
					when FUNCT3_BNE  => o_alu_op <= ALU_BNE;
					when FUNCT3_BLT  => o_alu_op <= ALU_BLT;
					when FUNCT3_BGE  => o_alu_op <= ALU_BGE;
					when FUNCT3_BLTU => o_alu_op <= ALU_BLTU;
					when FUNCT3_BGEU => o_alu_op <= ALU_BGEU;
					when others      => o_alu_op <= ALU_PASS_B;
				end case;

			-- -----------------------------------------------------------------------
			-- Leitura de memória de dados (I-type Load)
			-- -----------------------------------------------------------------------
			when OPCODE_LOAD =>
				o_ext_imm_op  <= EXT_IMM_I;
				o_wb_sel      <= WB_SEL_RAM;
				o_we_reg      <= '1';
				o_sel_rs2_imm <= '1';
				o_sel_pc_rs1  <= '1';
				o_alu_op      <= ALU_ADD;
				o_re_ram      <= '1';
				o_en_ram      <= '1';

				case funct3 is
					when FUNCT3_LW  => o_ext_ram_op <= EXT_RAM_LW;
					when FUNCT3_LH  => o_ext_ram_op <= EXT_RAM_LH;
					when FUNCT3_LHU => o_ext_ram_op <= EXT_RAM_LHU;
					when FUNCT3_LB  => o_ext_ram_op <= EXT_RAM_LB;
					when FUNCT3_LBU => o_ext_ram_op <= EXT_RAM_LBU;
					when others     => o_ext_ram_op <= EXT_RAM_LW;
				end case;

			-- -----------------------------------------------------------------------
			-- Escrita em memória de dados (S-type Store)
			-- -----------------------------------------------------------------------
			when OPCODE_STORE =>
				o_ext_imm_op  <= EXT_IMM_S;
				o_sel_rs2_imm <= '1';
				o_sel_pc_rs1  <= '1';
				o_alu_op      <= ALU_ADD;
				o_we_ram      <= '1';
				o_en_ram      <= '1';

			-- -----------------------------------------------------------------------
			-- Carregamento de imediato superior (U-type LUI)
			-- -----------------------------------------------------------------------
			when OPCODE_LUI =>
				o_ext_imm_op  <= EXT_IMM_U;
				o_we_reg      <= '1';
				o_sel_rs2_imm <= '1';
				o_alu_op      <= ALU_PASS_B;

			-- -----------------------------------------------------------------------
			-- Adição de imediato superior ao PC (U-type AUIPC)
			-- -----------------------------------------------------------------------
			when OPCODE_AUIPC =>
				o_ext_imm_op  <= EXT_IMM_U;
				o_we_reg      <= '1';
				o_sel_rs2_imm <= '1';
				o_alu_op      <= ALU_ADD;

			-- -----------------------------------------------------------------------
			-- Salto incondicional relativo ao PC (J-type JAL)
			-- -----------------------------------------------------------------------
			when OPCODE_JAL =>
				o_sel_pc4_alu <= '1';
				o_ext_imm_op  <= EXT_IMM_J;
				o_wb_sel      <= WB_SEL_PC4;
				o_we_reg      <= '1';
				o_sel_rs2_imm <= '1';
				o_alu_op      <= ALU_ADD;

			-- -----------------------------------------------------------------------
			-- Salto incondicional indireto via registrador (I-type JALR)
			-- -----------------------------------------------------------------------
			when OPCODE_JALR =>
				o_sel_pc4_alu <= '1';
				o_ext_imm_op  <= EXT_IMM_I;
				o_wb_sel      <= WB_SEL_PC4;
				o_we_reg      <= '1';
				o_sel_rs2_imm <= '1';
				o_sel_pc_rs1  <= '1';
				o_alu_op      <= ALU_JALR;

			when others =>
				null;

		end case;
	end process;

end architecture rtl;
