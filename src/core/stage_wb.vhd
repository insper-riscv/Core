-- =============================================================================
-- Estágio WB (Write-Back) do Pipeline RV32
--
-- Seleciona a palavra bruta retornada pelo subsistema de memória acessado no
-- ciclo anterior (FLASH porta 2, RAM interna ou SDRAM externa) usando as
-- constantes centralizadas em mem_map_consts, aplica o alinhamento e extensão
-- de sinal/zero para instruções de load (extender_ram) e seleciona o dado
-- final a ser gravado no banco de registradores (mux_4x1).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config_pkg.all;
use work.pipeline_types.all;
use work.byte_mask_consts.all;
use work.mem_map_consts.all;
use work.ext_ram_consts.all;

entity stage_wb is
    port (
        -- Bit de validade da instrução no estágio WB.
        i_valid       : in    std_logic;
        -- Resultado da ULA/execução (e bits [1:0] do endereço de load) no estágio WB.
        i_alu_out     : in    word_t;
        -- Índice do registrador destino rd no estágio WB.
        i_rd_idx      : in    reg_t;
        -- Habilitação de escrita no banco de registradores vinda do registrador MEM/WB.
        i_we_reg      : in    std_logic;
        -- Modo de extensão de leitura da memória de dados vindo do registrador MEM/WB.
        i_ext_ram_op  : in    ext_ram_op_t;
        -- Seletor de fonte de Write-Back vindo do registrador MEM/WB.
        i_wb_sel      : in    wb_sel_t;
        -- O endereço do load pertence à memória FLASH (decodificado no registrador MEM/WB).
        i_is_flash    : in    std_logic;
        -- O endereço do load pertence ao barramento externo de SDRAM (decodificado no registrador MEM/WB).
        i_is_sdram    : in    std_logic;
        -- O load cruza a palavra e usa a primeira palavra retida (decodificado no registrador MEM/WB).
        i_is_cross    : in    std_logic;
        -- Posição do dado dentro da palavra entregue ao extensor, zero no load que cruza (decodificada no MEM/WB).
        i_ext_off     : in    byte_offset_t;
        -- Deslocamento do load que cruza, um bit por byte, em zero fora do cruzamento (decodificado no MEM/WB).
        i_cross_sel   : in    std_logic_vector(2 downto 0);
        -- Palavra de dados lida da segunda porta da memória FLASH.
        i_flash_data2 : in    word_t;
        -- Palavra de dados lida da memória RAM interna.
        i_ram_rdata   : in    word_t;
        -- Primeira palavra de um load desalinhado que cruzou a palavra, retida pela misaligned_unit.
        i_first_word  : in    word_t;
        -- Palavra de dados lida do barramento externo SDRAM.
        i_ext_rdata   : in    word_t;
        -- Habilitação final de escrita enviada ao banco de registradores (reg_file).
        o_wb_we       : out   std_logic;
        -- Endereço final do registrador destino rd enviado ao banco de registradores.
        o_wb_rd       : out   reg_t;
        -- Dado final de 32 bits enviado ao banco de registradores e à malha de forwarding.
        o_wb_data     : out   word_t
    );
end entity stage_wb;

architecture rtl of stage_wb is

    -- Palavra bruta de 32 bits selecionada entre FLASH, SDRAM e RAM interna.
    signal mem_read_data   : word_t;
    -- Palavra de 32 bits alinhada e estendida pelo módulo extender_ram.
    signal wb_ram_extended : word_t;
    -- Palavra do load que cruzou, deslocada de um byte: o dado alinhado ao byte 0.
    signal cross_word1     : word_t;
    -- Palavra do load que cruzou, deslocada de dois bytes.
    signal cross_word2     : word_t;
    -- Palavra do load que cruzou, deslocada de três bytes.
    signal cross_word3     : word_t;
    -- Palavra entregue ao extensor: a juntada de duas palavras ou a lida da memória.
    signal ext_data        : word_t;

begin

    mem_read_data <= i_flash_data2 when i_is_flash = '1' else
                     i_ext_rdata when i_is_sdram = '1' else
                     i_ram_rdata;

    -- O par (mem_read_data, i_first_word) deslocado de um a três bytes; o deslocamento chega em um bit por byte.
    cross_word1 <= mem_read_data(7 downto 0) & i_first_word(31 downto 8);
    cross_word2 <= mem_read_data(15 downto 0) & i_first_word(31 downto 16);
    cross_word3 <= mem_read_data(23 downto 0) & i_first_word(31 downto 24);

    ext_data <= (mem_read_data and (word_t'range => not i_is_cross)) or
                (cross_word1 and (word_t'range => i_cross_sel(0))) or
                (cross_word2 and (word_t'range => i_cross_sel(1))) or
                (cross_word3 and (word_t'range => i_cross_sel(2)));

    u_extender_ram : entity work.extender_ram
        port map (
            i_data        => ext_data,
            i_op          => i_ext_ram_op,
            i_byte_offset => i_ext_off,
            o_data        => wb_ram_extended
        );

    u_mux_wb : entity work.mux_2x1
        generic map (
            data_width => word_t'length
        )
        port map (
            i_d0  => i_alu_out,
            i_d1  => wb_ram_extended,
            i_sel => i_wb_sel(0),
            o_d   => o_wb_data
        );

    o_wb_we <= i_we_reg and i_valid;
    o_wb_rd <= i_rd_idx;

end architecture rtl;
