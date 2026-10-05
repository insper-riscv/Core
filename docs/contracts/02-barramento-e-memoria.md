# 2. Interface de barramento e de memória

## O que existe hoje (verificado)

**Não existe barramento nem interface de memória definidos.** Existe o que o
`rv32im_pipeline_core` expõe como portas soltas, e duas decodificações de
endereço por comparação, dentro do core:

| Porta | Uso |
| :--- | :--- |
| `if_addr`, `if_rden`, `boot_rom_data`, `flash_data` | busca de instrução: as duas memórias respondem ao mesmo endereço todo ciclo; `is_boot_rom_if = if_pc < BOOT_ROM_SIZE_BYTES (0x800)` escolhe o dado |
| `flash_addr2`, `flash_rden2`, `flash_data2` | leitura de dado na FLASH (segunda porta física, artefato do Quartus Lite) |
| `ram_addr`, `ram_wdata`, `ram_rdata`, `ram_en`, `ram_wren`, `ram_rden`, `ram_byteena` | dado na RAM; `is_flash_data = addr < RAM_BASE_BYTES (0x8000)` roteia a leitura para a FLASH |

Propriedades implícitas, nunca escritas: **toda memória responde em exatamente
1 ciclo** (leitura síncrona, o dado chega em WB); não há sinal de "pronto";
escrita só na RAM; não existe caminho para periférico; o mapa
(`BOOT_ROM_SIZE_BYTES`, `RAM_BASE_BYTES`) é constante dentro do core.

**Periféricos:** `src/GPIO` e `src/TIMER` existem mas **não são instanciados em
nenhum topo vivo** (só o `L2IP`, depreciado, os referencia). A
forma deles é um barramento de fato, bem parecido entre os dois:

| | GPIO | TIMER |
| :--- | :--- | :--- |
| Sinais | `clock, clear, data_in, address(3:0), write, read, data_out, irq` | `clock, clear, data_in, address(2:0), write, read, data_out, irq` (+ `pwm`) |
| Dados | `DATA_WIDTH` = 32 | idem |

Sem `byteena`, sem `ready`, e o endereço é só o índice de registrador local. É o
ponto de partida natural do barramento.

## O que precisa ser definido

Antes de qualquer periférico ou memória externa:

1. **Um barramento de dados** (MEM stage → memórias e periféricos).
2. **Um sinal de "pronto"**, para latência variável.
3. **Quem decodifica o endereço** (hoje: comparações dentro do core).
4. **A busca de instrução** (IF), que tem requisitos diferentes (só leitura).

## O que o L2IP faz (verificado em `L2IP/hw/L2IP.vhd`)

O `L2IP` é um topo antigo (depreciado) que já integra GPIO e LEDs ao core. É a
única integração que existiu, e ela define um esquema de barramento de fato:

| Aspecto | Como o L2IP faz |
| :--- | :--- |
| Sinais do mestre (core) | os mesmos de hoje: `ram_addr`, `ram_wdata`, `ram_rdata`, `ram_en`, `ram_wren`, `ram_rden`, `ram_byteena` |
| Seleção de escravo | pelos bits altos do endereço: `bit31 = 1` e `addr(30:28)` = id do periférico |
| Mapa | `0x8...` RAM, `0x9...` LEDs (registrador de 8 bits), `0xA...` GPIO, `0xB...` TIMER (id reservado, **linha comentada, nunca ligado**) |
| Registrador dentro do periférico | bits baixos: GPIO `addr(5:2)` (4 bits), TIMER teria `addr(4:2)` |
| Strobes | `weGPIO = enable_gpio and ram_wren`, `reGPIO = enable_gpio and ram_rden`; o periférico recebe `write`/`read`/`address`/`data_in` |
| Leitura | mux combinacional: periférico escolhido pelo endereço, senão `ram_rdata` |
| Software | endereços absolutos em C (`0xA0000000` etc.), sem cabeçalho de plataforma |

O que isso mostra:
- **O esquema serve como base.** O endereçamento por bits altos é compatível
  com o mapa atual: hoje BOOT_ROM, FLASH e RAM ficam abaixo de `0x40000`
  (`bit31 = 0`), então periféricos em `bit31 = 1` não colidem com nada.
- **O L2IP não compila com o core atual.** Ele usa as portas antigas
  (`rom_addr`, `rom_data`, `rom_addr2`...), não as `if_*`/`boot_rom_data`/
  `flash_*` de hoje.
- **O TIMER nunca foi ligado.** Só o GPIO e os LEDs.
- **A leitura tem um risco de temporização a verificar:** o mux de leitura
  seleciona pelo endereço do estágio MEM, mas a RAM devolve o dado um ciclo
  depois (em WB), quando `ram_addr` já é de outra instrução. Com a RAM
  isso é coberto pelo caminho normal; para um periférico que responde na hora
  o seletor precisa ser registrado um ciclo, como o core já faz com
  `is_flash_data_wb`. O L2IP não faz isso.

## Proposta (a revisar), com o L2IP como base

### 2.1 Barramento de dados
**Adotar os sinais e o esquema do L2IP**, sem inventar um protocolo novo:

| Sinal | Dir. (core) | Significado |
| :--- | :--- | :--- |
| `addr(31:0)` | out | endereço de byte |
| `wdata(31:0)` | out | dado |
| `byteena(3:0)` | out | bytes válidos |
| `en`, `wren`, `rden` | out | acesso, escrita, leitura (como `ram_en/wren/rden`) |
| `rdata(31:0)` | in | dado lido (latência 1, como hoje) |

Acréscimo único, **opcional e só para memória externa**: `ready`
(`'1'` sempre nas memórias internas). Com `ready = '0'` o pipeline para na MEM
pelo mesmo mecanismo do `muldiv_stall`. Sem memória externa, não entra. A
primeira memória externa é a SDRAM (seção 2.5).

Convenções que o L2IP deixava implícitas e passam a escritas:
- **Janela por periférico:** `bit31 = 1`, `addr(30:28)` = id (`1` LEDs, `2` GPIO,
  `3` TIMER, `4` UART, reservado); o resto do endereço é o offset dentro do
  periférico.
- **Interface do periférico** (já é a do GPIO/TIMER): `clock, clear, data_in,
  address, write, read, data_out, irq`. `address` = offset de palavra local
  (`addr(N:2)`). `irq` fica fora do barramento e sem destino até o Zicsr.
- **Leitura de periférico:** seletor registrado um ciclo (corrige o risco acima).

### 2.2 Decodificação (interconnect)
Sai do core (`BOOT_ROM_SIZE_BYTES`, `RAM_BASE_BYTES`) para um bloco
`interconnect` no **TopLevel** que faz o que o L2IP fazia dentro do topo:
compara `addr` com as regiões do YAML de plataforma (doc 3) e gera o
`en/wren/rden` de cada escravo e o mux de leitura. Endereço fora de região:
leitura devolve 0, escrita sem efeito (sem exceções hoje).

### 2.3 Busca de instrução
Porta separada (`if_addr`, `if_rden`, `if_data`), só leitura, pelo mesmo
interconnect (BOOT_ROM e FLASH viram duas regiões executáveis). A leitura de
dado na FLASH (hoje a segunda porta física `FLASH_MEM`) é só uma região
legível pelo barramento de dados; o TopLevel decide a implementação física.

### 2.4 Famílias de memória (Memory)
Mesmo lado escravo em todas:

| Família | `ready` |
| :--- | :--- |
| Modelo de simulação (arrays VHDL) | sempre `'1'` |
| IP do Quartus (`altsyncram`) | sempre `'1'` (simula no GHDL via `altera_mf`) |
| Externa (SDRAM) | pelo controlador, vários ciclos |

### 2.5 Memória de latência variável (SDRAM)

Todo endereço de dado a partir de `0x40000000` sai por uma porta externa própria
do core, no mesmo padrão das portas da FLASH, em vez de passar pelo barramento
da RAM interna. O core não distingue quem responde: a SDRAM (64 MB a partir de
`0x40000000`, que numa plataforma sem RAM interna é a RAM) e as janelas de
periférico (`bit31 = 1`, seção 2.1) usam a mesma porta, e o bloco de fora
escolhe pelo endereço, devolvendo `ready` e dado do escolhido. Só dado: a busca
de instrução não alcança essa região. Os nomes das portas começam com `sdram`
e valem para toda a região externa:

| Porta | Dir. (core) | Significado |
| :--- | :--- | :--- |
| `sdram_addr`, `sdram_wdata`, `sdram_byteena` | out | endereço, dado e bytes válidos do acesso em MEM |
| `sdram_rden`, `sdram_wren` | out | leitura ou escrita pedida |
| `sdram_rdata` | in | dado lido |
| `sdram_ready` | in | `'0'` para o pipeline; vale `'1'` quando não há memória externa na plataforma |
| `mem_advance` | out | `'1'` no ciclo em que o pipeline anda |

Regras do handshake:

1. O acesso fica estável no barramento, com o EX/MEM parado, até `sdram_ready = '1'`.
2. `sdram_ready` fica em `'1'` como nível, até `mem_advance = '1'`. Um pulso de um ciclo não serve: se o muldiv também estiver parando, o pulso se perde e o acesso se repetiria.
3. `sdram_rdata` só muda na borda em que o pipeline anda, porque o load que está em WB ainda lê o valor anterior.
4. Um desvio tomado em EX não faz flush enquanto o pipeline está parado: o flush só vale quando o pipeline anda.

Sem memória externa na plataforma as portas ficam em aberto e o comportamento é o das memórias internas.

## Mudanças por repositório
- **Core**: trocar as portas soltas pela porta mestre + `if_*`; remover as
  constantes de mapa; o MEM para por `ready`.
- **Memory**: envolver os modelos atuais no lado escravo; nenhum muda de
  comportamento.
- **Peripherals**: adaptadores do GPIO/TIMER; testes por entidade.
- **TopLevel**: `interconnect` + instanciação conforme o YAML.
- **Tools/Testes**: nada muda enquanto `ready` for sempre `'1'`.

## Critério de aceite
As 89 provas de simulação dão o mesmo resultado com as memórias atrás do
interconnect (linha de base, `ready` sempre `'1'`), e um teste com um escravo
de latência variável (novo, em simulação) prova a parada do pipeline.

## Decisões

Decididas (sugestões aceitas):
- A busca de instrução só terá `ready` junto com memória externa.
- Endereço fora de região: leitura devolve 0, escrita sem efeito, até o Zicsr.
- Os ids de periférico do L2IP (`1` LEDs, `2` GPIO, `3` TIMER) ficam como estão; UART = `4`.
- `ready` não entra agora, só com memória externa.

- **Acesso desalinhado: opção A, no core** (decidido). O barramento é palavra de
  32 bits + `byteena`; o acesso realmente desalinhado não é suportado e fica
  documentado como indefinido até o Zicsr (falta o teste do comportamento atual).

Nenhuma dúvida em aberto neste documento. A análise que levou à decisão:

### Acesso desalinhado (verificado em `StoreManager.vhd` e `ExtenderRAM.vhd`)

"Desalinhado" mistura dois casos:

| Caso | Exemplo | Hoje |
| :--- | :--- | :--- |
| **Sub-palavra alinhada** | `lb`/`sb` em qualquer byte, `lh`/`sh` em endereço par | funciona, dentro do core |
| **Realmente desalinhado** | `lw` em `addr % 4 != 0`, `lh`/`sh` em `addr % 4 == 3` (cruza a palavra) | **não tratado**, e falha em silêncio |

Como o primeiro caso funciona: o barramento é sempre uma **palavra de 32 bits
com `byteena`**. No store, o `StoreManager` põe o dado na faixa de bytes certa
(`EA = addr(1:0)`) e gera o `byteena`. No load, a RAM devolve a palavra inteira e
o `ExtenderRAM` (em WB) escolhe a faixa e estende com sinal ou zero. O escravo
nunca sabe se foi `lb` ou `lw`: só vê palavra + `byteena`.

Como o segundo falha: o `lw` ignora `EA` (devolve a palavra alinhada abaixo),
e um `sh` com `EA = 11` cai no mesmo ramo do `EA = 10` (grava na metade alta).
Nenhuma exceção existe para avisar.

A pergunta é onde fica essa lógica de faixa:

| Opção | Como | Prós | Contras |
| :--- | :--- | :--- | :--- |
| **A. No core (recomendada)** | como hoje: o barramento é palavra + `byteena`, endereço de palavra | qualquer escravo (RAM, FLASH, periférico, memória externa) só precisa de uma interface simples; GPIO/TIMER (registradores de 32 bits) ignoram `byteena` | o core carrega `StoreManager` e `ExtenderRAM` |
| B. No escravo | o barramento leva tamanho (`byte/half/word`) e o endereço exato; cada escravo alinha | core menor | cada escravo repete a lógica; a chance de erro cresce a cada memória/periférico novo |

**Decisão: A**, que é o que já funciona e já está validado. Sobre o caso
realmente desalinhado, propõe-se **não suportar e dizer isso no contrato**:
o resultado é indefinido hoje (sem exceção); quando o Zicsr existir vira a
exceção `address misaligned` (causa 4/6). Compiladores geram acesso alinhado
(e o `memcpy` da picolibc é por byte, verificado antes). Falta um teste que
documente o comportamento atual, para que a mudança futura seja visível.

