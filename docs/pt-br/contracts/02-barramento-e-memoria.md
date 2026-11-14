# 2. Interface de Barramento e Mapa de Memória

## 1. Mapa de Endereços do Processador

Os limites do espaço de endereçamento de instruções (estágio IF) e de dados (estágios MEM e WB) chegam aos estágios como constantes do `config_pkg`, que o `riscv-tools` gera do `platform.yaml` de cada plataforma. O núcleo conhece só três regiões, a Memória de boot, a FLASH e a RAM. O pacote `src/shared/mem_map_consts.vhd` traz as funções que os estágios usam para decidir a região de um endereço a partir dessas constantes.

| Constante do `config_pkg` | Padrão | Região demarcada |
| :--- | :--- | :--- |
| `BOOT_MEMORY_BASE`, `BOOT_MEMORY_END` | `0`, `0x00001000` | A Memória de boot ocupa `[0, 2**BOOT_MEMORY_BITS)`, ou seja `0x00000000 .. 0x00000FFF` por padrão, e sempre é alcançada pela porta direta |
| `FLASH_BASE`, `FLASH_END` | `0x00001000`, `0x00008000` | Faixa da FLASH em bytes, com o fim exclusivo (`0x00001000 .. 0x00007FFF` por padrão); precisa ter tamanho positivo e começar depois da Memória de boot |
| `FLASH_ON_BUS` | `false` | Falso, a FLASH é alcançada pela porta direta do núcleo, de latência fixa e sem handshake; verdadeiro, pelo barramento (`o_ext_*` e a porta de instruções), dentro ou fora do chip |
| `RAM_BASE`, `RAM_END` | `0x00008000`, `0x40000000` | Faixa da RAM em bytes, com o fim exclusivo (`0x00008000 .. 0x3FFFFFFF` por padrão); começa depois da FLASH |
| `RAM_ON_BUS` | `false` | Falso, a RAM é alcançada pela porta direta (`o_ram_*`); verdadeiro, pelo barramento (`o_ext_*`) |
| `HAS_ICACHE`, `HAS_DCACHE` | `false` | A cache de instruções exige `FLASH_ON_BUS` e a cache de dados exige `RAM_ON_BUS`; o `check_isa` recusa as outras combinações |

O caminho de um acesso segue a região, e não o papel dele:

| Região | Busca, load ou store |
| :--- | :--- |
| Memória de boot | Porta direta |
| FLASH | Porta direta com `FLASH_ON_BUS` falso, barramento com ele verdadeiro |
| RAM | Porta direta com `RAM_ON_BUS` falso, barramento com ele verdadeiro |
| Fora das três regiões | Barramento (porta externa); sem escravo que atenda o endereço, a porta externa responde erro |

O papel do acesso só escolhe a cache, e só quando a região está no barramento: a busca passa pela cache de instruções e o load e o store pela cache de dados. Cada região sai da comparação do endereço com limites constantes, e as bases que são potências de 2 viram testes de bits na síntese. Não há mais janela de periféricos nem janela externa no núcleo: quem decodifica os periféricos é o interconector, fora do núcleo.

A Memória de boot e a FLASH são só de leitura, então um store a elas gera a falha de acesso de store (causa 7, com `HAS_ACCESS_FAULTS`). A busca de instrução só é válida na Memória de boot, na FLASH e, com `RAM_ON_BUS`, na RAM (pela cache de instruções); fora daí, `HAS_ACCESS_FAULTS` gera a falha de acesso de instrução (causa 1). O acesso desalinhado em hardware atende a memória principal, que é tudo o que não é a Memória de boot nem a FLASH direta, e não atravessa o fim de uma região de caminho próprio.

## 2. Interfaces de Busca de Instruções (Estágio IF)

O estágio IF (`src/core/stage_if.vhd`) apresenta o endereço atual do PC em `o_if_addr` com `o_if_rden = '1'` e seleciona a instrução conforme a região do endereço:

| Porta no topo `core` | Direção | Região de endereço | Descrição |
| :--- | :--- | :--- | :--- |
| `o_if_addr` | `out` (`addr_t`) | Todas | Endereço de byte do Program Counter atual |
| `o_if_rden` | `out` | Todas | Habilitação de leitura de instrução (fixa em `'1'`) |
| `i_boot_memory_data` | `in` | Memória de boot | Palavra de instrução de 32 bits retornada pela Memória de boot |
| `i_flash_data` | `in` | FLASH com `FLASH_ON_BUS` falso | Palavra de instrução de 32 bits retornada pela porta 1 da memória Flash |
| `o_ic_sel` | `out` | Barramento | Indica que o PC atual aponta para a região atendida pela cache de instruções externa (a FLASH com `FLASH_ON_BUS`, a RAM com `RAM_ON_BUS` e o que está fora das três regiões) |
| `i_ic_data` | `in` | Barramento | Palavra de instrução de 32 bits fornecida pela cache de instruções externa |
| `i_ic_ready` | `in` | Barramento | Sinaliza que `i_ic_data` contém a instrução válida para `o_if_addr`; enquanto vale `'0'` com `o_ic_sel = '1'`, o PC congela e `reg_if_id` recebe bolha (`i_valid = '0'`) |
| `o_ic_inval` | `out` | Controle de cache | Pulso de 1 ciclo gerado na conclusão de uma instrução `FENCE.I` para invalidar a cache de instruções externa |

## 3. Interfaces de Memória de Dados (Estágios MEM e WB)

No estágio MEM (`src/core/stage_mem.vhd`), o endereço efetivo calculado no estágio EX é roteado para uma das três interfaces de dados. No estágio WB (`src/core/stage_wb.vhd`), o dado lido correspondente é selecionado e alinhado pelo módulo `src/I-E/extender_ram.vhd`.

### 3.1. Porta de Dados da Memória Flash (Memória de boot e FLASH direta)

Utilizada para leitura de constantes (`.rodata`) e cópia da seção `.data` na inicialização, com latência síncrona fixa de 1 ciclo. Atende a Memória de boot e, com `FLASH_ON_BUS` falso, a FLASH:

| Porta no topo `core` | Direção | Estágio | Significado |
| :--- | :--- | :--- | :--- |
| `o_flash_addr2` | `out` (`addr_t`) | MEM | Endereço de byte da leitura na Flash |
| `o_flash_rden2` | `out` | MEM | Habilitação de leitura (`exmem_re_ram and exmem_valid and is_flash_data`) |
| `i_flash_data2` | `in` | WB | Palavra de 32 bits retornada no ciclo seguinte |

### 3.2. Memória RAM Direta (`[RAM_BASE, RAM_END)` com `RAM_ON_BUS` falso)

Memória de dados síncrona de 1 ciclo de latência com escrita controlada por máscara de bytes:

| Porta no topo `core` | Direção | Estágio | Significado |
| :--- | :--- | :--- | :--- |
| `o_ram_addr` | `out` (`addr_t`) | MEM | Endereço de byte do acesso |
| `o_ram_wdata` | `out` | MEM | Palavra de 32 bits com os bytes de escrita posicionados pelo `store_manager` |
| `o_ram_byteena` | `out` | MEM | Máscara de 4 bits indicando quais bytes de `o_ram_wdata` devem ser escritos |
| `o_ram_en` | `out` | MEM | Habilitação geral da RAM direta |
| `o_ram_wren` | `out` | MEM | Habilitação de escrita na RAM direta |
| `o_ram_rden` | `out` | MEM | Habilitação de leitura na RAM direta |
| `i_ram_rdata` | `in` | WB | Palavra de 32 bits lida da RAM direta no ciclo seguinte |

### 3.3. Porta Externa de Latência Variável (barramento)

Todo acesso de leitura ou escrita que as duas portas diretas não atendem utiliza a porta mestre externa do processador: a FLASH com `FLASH_ON_BUS`, a RAM com `RAM_ON_BUS` e todo endereço fora da Memória de boot, da FLASH e da RAM:

| Porta no topo `core` | Direção | Estágio | Significado |
| :--- | :--- | :--- | :--- |
| `o_ext_addr` | `out` (`addr_t`) | MEM | Endereço de byte do acesso externo |
| `o_ext_wdata` | `out` | MEM | Dado de 32 bits alinhado para escrita |
| `o_ext_byteena` | `out` | MEM | Máscara de habilitação de bytes (4 bits) |
| `o_ext_rden` | `out` | MEM | Requisição de leitura ativa enquanto o acesso válido estiver em MEM |
| `o_ext_wren` | `out` | MEM | Requisição de escrita ativa enquanto o acesso válido estiver em MEM |
| `i_ext_rdata` | `in` | WB | Palavra de 32 bits retornada pelo escravo externo |
| `i_ext_ready` | `in` | MEM | Nível lógico que indica conclusão da transação externa (`'0'` retém o pipeline; padrão `'1'` quando desconectado) |
| `i_ext_error` | `in` | MEM | Nível lógico levantado junto com `i_ext_ready` quando nenhum escravo atende o endereço (padrão `'0'` quando desconectado) |
| `o_mem_advance` | `out` | Global | Indica ao escravo externo que o estágio MEM avançou na borda de clock atual (`base_run = '1'`) |

Regras do protocolo de handshake externo:

1. **Estabilidade durante espera:** enquanto `sdram_access = '1'` e `i_ext_ready = '0'`, o sinal `o_ext_wait` mantém `base_run = '0'`, congelando `reg_ex_mem` e mantendo `o_ext_addr`, `o_ext_wdata`, `o_ext_byteena`, `o_ext_rden` e `o_ext_wren` estáveis.
2. **Confirmação em nível (`i_ext_ready`):** o escravo externo deve manter `i_ext_ready = '1'` até observar `o_mem_advance = '1'`, garantindo que a conclusão não seja perdida caso a unidade `multdiv` também esteja retendo o pipeline no mesmo ciclo.
3. **Preservação do dado lido (`i_ext_rdata`):** a palavra `i_ext_rdata` permanece estável até o ciclo WB em que a instrução de load é consumida por `stage_wb`.
4. **Inibição de flush por desvio durante espera:** desvios e saltos tomados no estágio EX só aplicam flush em `reg_if_id` e `reg_id_ex` quando `pipe_run = '1'`, preservando a instrução de desvio em EX até que o acesso em MEM termine.
5. **Resposta de erro (`i_ext_error`):** o escravo levanta `i_ext_error = '1'` no mesmo ciclo de `i_ext_ready = '1'` quando nenhum escravo atende o endereço, e a transação não tem efeito no escravo. Com `HAS_ACCESS_FAULTS`, o estágio MEM gera nesse ciclo a falha de acesso de load (`mcause = 5`) ou de store (`mcause = 7`), com o endereço efetivo em `mtval` e o `mepc` da própria instrução, pelo mesmo caminho da exceção de endereço (`mem_trap_take`): a instrução de EX é descartada, o load não escreve registrador e a contagem de `minstret` não a inclui. Num acesso desalinhado que ocupa duas palavras, o erro de qualquer uma das duas gera a falha do acesso. Sem `HAS_ACCESS_FAULTS`, o erro é ignorado.

O contrato K1 é esta porta externa. Nele, o prefixo das portas é `ext` (`o_ext_*` e `i_ext_*`) e o comportamento é o das regras acima, o mesmo para qualquer região por trás dela: um backend emulado (memória interna do FPGA) ou um backend de dispositivo (o chip da placa). O núcleo vê só o handshake, e nunca o que realiza a região.

## 4. Alinhamento de Sub-palavra e Exceções de Desalinhamento

O barramento de dados opera sempre sobre palavras de 32 bits acompanhadas de `byteena`:

- **Acessos naturalmente alinhados (`LB`/`LBU`/`SB` em qualquer endereço, `LH`/`LHU`/`SH` em endereços pares, `LW`/`SW` em múltiplos de 4):** no store, `src/I-E/store_manager.vhd` replica o byte ou meia-palavra nas lanes correspondentes aos bits `ea[1:0]` e ativa os bits respectivos da máscara `o_byte_mask`; no load, `src/I-E/extender_ram.vhd` extrai a faixa selecionada por `ea[1:0]` e aplica extensão de sinal ou zero no estágio WB.
- **Acessos desalinhados (`LW`/`SW` com `ea[1:0] /= "00"` ou `LH`/`LHU`/`SH` com `ea[0] = '1'`):** com `HAS_ZICCLSM = true` (extensão Zicclsm), o hardware executa o acesso quando ele cai na memória principal, que é tudo o que não é a Memória de boot nem a FLASH direta. Um acesso que cabe numa palavra (`LH`, `LHU` e `SH` com `ea[1:0] = "01"`) completa num ciclo, e um acesso que ocupa duas palavras (`LW` e `SW` com offset 1 a 3, `LH`, `LHU` e `SH` com offset 3) roda em duas etapas na `misaligned_unit`. Na etapa 1 o pipeline espera e a unidade apresenta a palavra do primeiro byte, na etapa 2 apresenta a palavra seguinte, e o estágio WB junta as duas palavras de um load. O acesso que cruza a palavra não é atômico, porque a primeira metade pode ter sido escrita quando a segunda falha. As duas palavras precisam estar na mesma região, e um acesso fora da memória principal ou entre regiões é um acesso que o hardware não executa. Com `HAS_ZICSR = true`, a unidade `src/Zicsr/trap_unit.vhd` detecta esse acesso no estágio EX, anula a instrução antes que ela alcance o estágio MEM (`flush_ex_mem = '1'`) e dispara exceção síncrona com `mcause = 4` (Load Address Misaligned) ou `mcause = 6` (Store Address Misaligned), gravando o endereço efetivo `i_ea` em `mtval`. Com `HAS_ZICCLSM = false` todo acesso desalinhado é um acesso que o hardware não executa, e essa combinação exige `HAS_ZICSR = true`, caso contrário a elaboração falha.

## 5. Exceções Sem Zicsr

Sem Zicsr o core não tem CSRs para registrar uma exceção. O detector de causas continua ativo, e uma exceção é sinalizada nas saídas do `core`, sem redirecionar o PC.

| Saída | Significado |
| :--- | :--- |
| `o_trap` | Pulso de um ciclo em `'1'` quando uma exceção ocorre |
| `o_trap_cause` | Código de causa no formato do `mcause` (2 instrução ilegal, 3 `EBREAK`, 4 e 6 acesso desalinhado que o hardware não executa, 11 `ECALL`) |
| `o_trap_pc` | PC da instrução que gerou a exceção |
| `o_trap_take` | Pulso de um ciclo em `'1'` quando o core toma uma exceção, com ou sem Zicsr (com Zicsr, `o_trap` fica em `'0'` e este pulso é o único sinal externo) |

A instrução que gerou a exceção é anulada no estágio EX, sem escrita em `rd` e sem acesso à memória, e o programa segue na instrução seguinte. Qualquer instrução CSR é ilegal sem Zicsr, e um desvio para endereço desalinhado não é checado. Com Zicsr, `o_trap` fica em `'0'` e as outras duas saídas ficam em zero. Quem decide o que fazer com o sinal é o ambiente em volta do core.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
