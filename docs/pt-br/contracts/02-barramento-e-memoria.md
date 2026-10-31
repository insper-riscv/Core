# 2. Interface de Barramento e Mapa de Memória

## 1. Mapa de Endereços do Processador

Os limites do espaço de endereçamento de instruções (estágio IF) e de dados (estágios MEM e WB) são centralizados no pacote `common/mem_map_consts.vhd`:

| Constante (`mem_map_consts`) | Valor | Região demarcada |
| :--- | :--- | :--- |
| `BOOT_ROM_SIZE_BYTES` | `0x00000800` (2 KiB) | Fim da janela da Boot ROM (`0x00000000 .. 0x000007FF`) no estágio IF |
| `RAM_BASE_BYTES` | `0x00008000` (32 KiB) | Base da memória RAM interna de dados (`0x00008000 .. 0x3FFFFFFF`); endereços de dados abaixo deste limite acessam a segunda porta da memória Flash |
| `SDRAM_BASE_BYTES` | `0x40000000` (1 GiB) | Base da janela externa de SDRAM e periféricos mapeados em memória (`0x40000000 .. 0xFFFFFFFF`) |
| `FLASH_EXT_BASE_BYTES` | `0x20000000` | Base da FLASH externa no mapa da plataforma sdram |
| `PERIPHERAL_BASE_BYTES` | `0x80000000` | Base da janela de periféricos dentro da janela externa |

As fronteiras são potências de 2. Cada base é calculada a partir do índice do seu único bit em `'1'`, e os estágios decodificam a região testando esse bit do endereço, sem comparador numérico.

| Constante (`mem_map_consts`) | Valor | Base derivada |
| :--- | :--- | :--- |
| `RAM_BASE_BIT` | 15 | `RAM_BASE_BYTES` |
| `FLASH_EXT_BASE_BIT` | 29 | `FLASH_EXT_BASE_BYTES` |
| `SDRAM_BASE_BIT` | 30 | `SDRAM_BASE_BYTES` |
| `PERIPHERAL_BASE_BIT` | 31 | `PERIPHERAL_BASE_BYTES` |

## 2. Interfaces de Busca de Instruções (Estágio IF)

O estágio IF (`core/stage_if.vhd`) apresenta o endereço atual do PC em `o_if_addr` com `o_if_rden = '1'` e seleciona a instrução conforme a faixa de endereço:

| Porta no topo `core` | Direção | Região de endereço | Descrição |
| :--- | :--- | :--- | :--- |
| `o_if_addr` | `out` | Todas | Endereço de byte do Program Counter atual |
| `o_if_rden` | `out` | Todas | Habilitação de leitura de instrução (fixa em `'1'`) |
| `i_boot_rom_data` | `in` | `< 0x00000800` | Palavra de instrução de 32 bits retornada pela Boot ROM |
| `i_flash_data` | `in` | `0x00000800 .. 0x3FFFFFFF` | Palavra de instrução de 32 bits retornada pela porta 1 da memória Flash |
| `o_ic_sel` | `out` | `>= 0x40000000` | Indica que o PC atual aponta para a região atendida pela cache de instruções externa (SDRAM) |
| `i_ic_data` | `in` | `>= 0x40000000` | Palavra de instrução de 32 bits fornecida pela cache de instruções externa |
| `i_ic_ready` | `in` | `>= 0x40000000` | Sinaliza que `i_ic_data` contém a instrução válida para `o_if_addr`; enquanto vale `'0'` com `o_ic_sel = '1'`, o PC congela e `reg_if_id` recebe bolha (`i_valid = '0'`) |
| `o_ic_inval` | `out` | Controle de cache | Pulso de 1 ciclo gerado na conclusão de uma instrução `FENCE.I` para invalidar a cache de instruções externa |

## 3. Interfaces de Memória de Dados (Estágios MEM e WB)

No estágio MEM (`core/stage_mem.vhd`), o endereço efetivo calculado no estágio EX é roteado para uma das três interfaces de dados. No estágio WB (`core/stage_wb.vhd`), o dado lido correspondente é selecionado e alinhado pelo módulo `I/extender_ram.vhd`.

### 3.1. Porta de Dados da Memória Flash (`< 0x00008000`)

Utilizada para leitura de constantes (`.rodata`) e cópia da seção `.data` na inicialização, com latência síncrona fixa de 1 ciclo:

| Porta no topo `core` | Direção | Estágio | Significado |
| :--- | :--- | :--- | :--- |
| `o_flash_addr2` | `out` | MEM | Endereço de byte da leitura na Flash |
| `o_flash_rden2` | `out` | MEM | Habilitação de leitura (`exmem_re_ram and exmem_valid and is_flash_data`) |
| `i_flash_data2` | `in` | WB | Palavra de 32 bits retornada no ciclo seguinte |

### 3.2. Memória RAM Interna (`0x00008000 .. 0x3FFFFFFF`)

Memória de dados síncrona de 1 ciclo de latência com escrita controlada por máscara de bytes:

| Porta no topo `core` | Direção | Estágio | Significado |
| :--- | :--- | :--- | :--- |
| `o_ram_addr` | `out` | MEM | Endereço de byte do acesso |
| `o_ram_wdata` | `out` | MEM | Palavra de 32 bits com os bytes de escrita posicionados pelo `store_manager` |
| `o_ram_byteena` | `out` | MEM | Máscara de 4 bits indicando quais bytes de `o_ram_wdata` devem ser escritos |
| `o_ram_en` | `out` | MEM | Habilitação geral da RAM interna |
| `o_ram_wren` | `out` | MEM | Habilitação de escrita na RAM interna |
| `o_ram_rden` | `out` | MEM | Habilitação de leitura na RAM interna |
| `i_ram_rdata` | `in` | WB | Palavra de 32 bits lida da RAM interna no ciclo seguinte |

### 3.3. Barramento Externo de Latência Variável: SDRAM e Periféricos (`>= 0x40000000`)

Todo acesso de leitura ou escrita com endereço a partir de `0x40000000` utiliza a porta mestre externa do processador:

| Porta no topo `core` | Direção | Estágio | Significado |
| :--- | :--- | :--- | :--- |
| `o_sdram_addr` | `out` | MEM | Endereço de byte do acesso externo |
| `o_sdram_wdata` | `out` | MEM | Dado de 32 bits alinhado para escrita |
| `o_sdram_byteena` | `out` | MEM | Máscara de habilitação de bytes (4 bits) |
| `o_sdram_rden` | `out` | MEM | Requisição de leitura ativa enquanto o acesso válido estiver em MEM |
| `o_sdram_wren` | `out` | MEM | Requisição de escrita ativa enquanto o acesso válido estiver em MEM |
| `i_sdram_rdata` | `in` | WB | Palavra de 32 bits retornada pelo escravo externo |
| `i_sdram_ready` | `in` | MEM | Nível lógico que indica conclusão da transação externa (`'0'` retém o pipeline; padrão `'1'` quando desconectado) |
| `o_mem_advance` | `out` | Global | Indica ao escravo externo que o estágio MEM avançou na borda de clock atual (`base_run = '1'`) |

Regras do protocolo de handshake externo:

1. **Estabilidade durante espera:** enquanto `sdram_access = '1'` e `i_sdram_ready = '0'`, o sinal `o_sdram_wait` mantém `base_run = '0'`, congelando `reg_ex_mem` e mantendo `o_sdram_addr`, `o_sdram_wdata`, `o_sdram_byteena`, `o_sdram_rden` e `o_sdram_wren` estáveis.
2. **Confirmação em nível (`i_sdram_ready`):** o escravo externo deve manter `i_sdram_ready = '1'` até observar `o_mem_advance = '1'`, garantindo que a conclusão não seja perdida caso a unidade `multdiv` também esteja retendo o pipeline no mesmo ciclo.
3. **Preservação do dado lido (`i_sdram_rdata`):** a palavra `i_sdram_rdata` permanece estável até o ciclo WB em que a instrução de load é consumida por `stage_wb`.
4. **Inibição de flush por desvio durante espera:** desvios e saltos tomados no estágio EX só aplicam flush em `reg_if_id` e `reg_id_ex` quando `pipe_run = '1'`, preservando a instrução de desvio em EX até que o acesso em MEM termine.

## 4. Alinhamento de Sub-palavra e Exceções de Desalinhamento

O barramento de dados opera sempre sobre palavras de 32 bits acompanhadas de `byteena`:

- **Acessos naturalmente alinhados (`LB`/`LBU`/`SB` em qualquer endereço, `LH`/`LHU`/`SH` em endereços pares, `LW`/`SW` em múltiplos de 4):** no store, `I/store_manager.vhd` replica o byte ou meia-palavra nas lanes correspondentes aos bits `ea[1:0]` e ativa os bits respectivos da máscara `o_byte_mask`; no load, `I/extender_ram.vhd` extrai a faixa selecionada por `ea[1:0]` e aplica extensão de sinal ou zero no estágio WB.
- **Acessos desalinhados (`LW`/`SW` com `ea[1:0] /= "00"` ou `LH`/`LHU`/`SH` com `ea[0] = '1'`):** com `has_zicclsm = true` (extensão Zicclsm), o hardware executa o acesso quando ele cai na memória principal, que é a RAM interna e a SDRAM. Um acesso que cabe numa palavra (`LH`, `LHU` e `SH` com `ea[1:0] = "01"`) completa num ciclo, e um acesso que ocupa duas palavras (`LW` e `SW` com offset 1 a 3, `LH`, `LHU` e `SH` com offset 3) roda em duas etapas na `misaligned_unit`. Na etapa 1 o pipeline espera e a unidade apresenta a palavra do primeiro byte, na etapa 2 apresenta a palavra seguinte, e o estágio WB junta as duas palavras de um load. O acesso que cruza a palavra não é atômico, porque a primeira metade pode ter sido escrita quando a segunda falha. As duas palavras precisam estar na mesma região, e um acesso fora da memória principal ou entre regiões é um acesso que o hardware não executa. Com `has_zicsr = true`, a unidade `Zicsr/trap_unit.vhd` detecta esse acesso no estágio EX, anula a instrução antes que ela alcance o estágio MEM (`flush_ex_mem = '1'`) e dispara exceção síncrona com `mcause = 4` (Load Address Misaligned) ou `mcause = 6` (Store Address Misaligned), gravando o endereço efetivo `i_ea` em `mtval`. Com `has_zicclsm = false` todo acesso desalinhado é um acesso que o hardware não executa, e essa combinação exige `has_zicsr = true`, caso contrário a elaboração falha.

## 5. Exceções Sem Zicsr

Sem Zicsr o core não tem CSRs para registrar uma exceção. O detector de causas continua ativo, e uma exceção é sinalizada nas saídas do `core`, sem redirecionar o PC.

| Saída | Significado |
| :--- | :--- |
| `o_trap` | Pulso de um ciclo em `'1'` quando uma exceção ocorre |
| `o_trap_cause` | Código de causa no formato do `mcause` (2 instrução ilegal, 3 `EBREAK`, 4 e 6 acesso desalinhado que o hardware não executa, 11 `ECALL`) |
| `o_trap_pc` | PC da instrução que gerou a exceção |

A instrução que gerou a exceção é anulada no estágio EX, sem escrita em `rd` e sem acesso à memória, e o programa segue na instrução seguinte. Qualquer instrução CSR é ilegal sem Zicsr, e um desvio para endereço desalinhado não é checado. Com Zicsr, `o_trap` fica em `'0'` e as outras duas saídas ficam em zero. Quem decide o que fazer com o sinal é o ambiente em volta do core.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
