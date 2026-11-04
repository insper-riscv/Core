# Zicclsm: Implementação no Core

A Zicclsm é a extensão, definida na especificação de perfis do RISC-V, que exige loads e stores desalinhados executados sem exceção na memória principal. Este documento descreve como o Core executa esses acessos e qual é o caminho de uma instrução desalinhada pelo pipeline. O que a especificação exige, com as fontes, está em [instructions.md](instructions.md). O genérico `has_zicclsm` (padrão `true`) liga e desliga a extensão.

## 1. Classificação dos Acessos

O alinhamento de um acesso depende da largura da instrução e dos dois bits menos significativos do endereço efetivo, o deslocamento $o = \text{ea}[1:0]$.

| Instrução | $o = 0$ | $o = 1$ | $o = 2$ | $o = 3$ |
| :--- | :--- | :--- | :--- | :--- |
| `LB`, `LBU`, `SB` | Alinhado | Alinhado | Alinhado | Alinhado |
| `LH`, `LHU`, `SH` | Alinhado | Dentro da palavra | Alinhado | Cruza a palavra |
| `LW`, `SW` | Alinhado | Cruza a palavra | Cruza a palavra | Cruza a palavra |

| Classe | Execução | Custo |
| :--- | :--- | :--- |
| Alinhado | Um acesso à memória | Nenhum ciclo extra |
| Dentro da palavra | Um acesso, com os bytes escolhidos pelo deslocamento | Nenhum ciclo extra |
| Cruza a palavra | Dois acessos a palavras consecutivas | Um ciclo extra na RAM interna |

Um acesso que cruza a palavra ocupa os bytes finais de uma palavra de 32 bits e os bytes iniciais da seguinte.

## 2. Quando o Hardware Executa o Acesso

O Core trata como memória principal, para efeito da extensão, as regiões de dados que ficam entre o fim da ROM interna (ou a base externa, quando a ROM é externa) e a base da janela de periféricos. Os limites vêm dos genéricos do mapa de memória (`rom_end_kib`, `rom_external`, `ram_base_kib`, `ram_end_kib`, `ext_base_kib` e `periph_base_kib`), descritos em [02-barramento-e-memoria.md](../../contracts/02-barramento-e-memoria.md).

O início da memória principal é `ext_base_kib * 1024` quando `rom_external` é verdadeiro e `rom_end_kib` vale 0, `2 ** boot_rom_bits` (o fim da BOOT_ROM, `0x00001000` por padrão) quando `rom_external` é verdadeiro e `rom_end_kib` é maior que 0, e `rom_end_kib * 1024` nos demais casos. O fim é `periph_base_kib * 1024`, onde começa a janela de periféricos. Os intervalos abaixo são semiabertos e valem para qualquer valor dos genéricos.

| Região | Faixa em função dos genéricos | Acesso desalinhado em hardware |
| :--- | :--- | :--- |
| Abaixo da memória principal (BOOT_ROM, ROM interna e faixa sem memória) | `[0, início)` | Não, gera exceção |
| Memória principal | `[início, periph_base_kib * 1024)` | Sim |
| Periféricos | `[periph_base_kib * 1024, 2**32)` | Não, gera exceção |

Cada plataforma fixa os genéricos no seu `config.yml`. A tabela mostra os dois mapas usados hoje, com a memória principal e os periféricos já convertidos em endereços.

| Mapa | `rom_external` | `rom_end_kib` | `ext_base_kib` | `periph_base_kib` | Memória principal | Periféricos |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| Padrão, com RAM interna | `false` | 32 | 1048576 | 2097152 | `0x00008000` a `0x7FFFFFFF` | `0x80000000` em diante |
| Plataforma com FLASH externa | `true` | 0 | 524288 | 1572864 | `0x20000000` a `0x5FFFFFFF` | `0x60000000` em diante |

Um acesso desalinhado que cabe numa palavra (`LH`, `LHU` e `SH` com $o = 1$) é executado quando o endereço está na memória principal. Um acesso que cruza a palavra é executado apenas quando atende às duas condições abaixo.

1. O endereço está na memória principal do mapa em uso.
2. O endereço não pertence à última palavra de uma região. As duas palavras do acesso precisam ficar na mesma região, e a palavra seguinte à última de cada região pertence à região vizinha, mesmo quando os endereços são contíguos (por exemplo, `0x3FFFFFFC` no mapa padrão).

Quando alguma condição falha, ou quando `has_zicclsm` é falso, o acesso gera exceção de endereço desalinhado. A instrução é anulada antes de acessar a memória, o que ocorre no estágio MEM quando o Core tem Zicsr e no estágio EX quando não tem. Com Zicsr ativo, a exceção usa `mcause = 4` para load e `mcause = 6` para store, e `mtval` recebe o endereço efetivo. Sem Zicsr, a exceção é só sinalizada nas saídas do Core, como descrito em [02-barramento-e-memoria.md](../../contracts/02-barramento-e-memoria.md). A combinação sem Zicsr e sem Zicclsm é uma configuração válida.

## 3. Acesso Que Cruza a Palavra

Um acesso que cruza a palavra roda em duas etapas, ambas no estágio MEM.

| Etapa | Endereço apresentado | Dado e máscara de store | Pipeline |
| :--- | :--- | :--- | :--- |
| 1 | Palavra do primeiro byte | Bytes que cabem nessa palavra | Parado até a etapa concluir |
| 2 | Palavra seguinte, $\text{palavra} + 4$ | Bytes restantes | Avança normalmente |

Um flip-flop indica a etapa corrente. Ele passa a `1` quando a etapa 1 conclui e volta a `0` quando a instrução deixa o estágio MEM.

A etapa 1 conclui quando duas condições valem no mesmo ciclo.

- O escravo está pronto. A RAM interna sempre está, pois responde em um ciclo. As regiões externas (a SDRAM e, no mapa com FLASH externa, também a FLASH) só estão quando o sinal de pronto chega.
- A memória pode avançar, isto é, o pipeline não está parado por multiplicação ou divisão nem por espera de região externa.

Durante a etapa 1 o sinal de parada da unidade congela os estágios anteriores e mantém a instrução em MEM. Na etapa 2 esse sinal desce, e a instrução sai de MEM quando o pipeline avança, como um acesso alinhado. Na RAM interna a etapa 1 conclui no primeiro ciclo, de modo que a instrução ocupa o estágio MEM por dois ciclos em vez de um.

## 4. Store Que Cruza a Palavra

O store chega ao MEM já posicionado pelo gerenciador de stores. O `SW` traz o registrador inteiro, e o `SH` no deslocamento 3 traz a meia palavra em `[31:16]`. A unidade normaliza o dado para os bytes baixos, desloca-o de $8o$ bits e a máscara de $o$ bits, num par de 64 bits e 8 bits. A etapa 1 escreve a metade baixa e a etapa 2 escreve a metade alta.

$$
\text{dado}_{64} = \text{dado} \ll 8o \qquad \text{máscara}_8 = \text{máscara} \ll o
$$

| Instrução | $o$ | Etapa 1 (bytes escritos) | Etapa 2 (bytes escritos) |
| :--- | :--- | :--- | :--- |
| `SW` | 1 | bytes 1, 2 e 3 (máscara `1110`) | byte 0 (máscara `0001`) |
| `SW` | 2 | bytes 2 e 3 (máscara `1100`) | bytes 0 e 1 (máscara `0011`) |
| `SW` | 3 | byte 3 (máscara `1000`) | bytes 0, 1 e 2 (máscara `0111`) |
| `SH` | 3 | byte 3 (máscara `1000`) | byte 0 (máscara `0001`) |

Em loads a máscara é zero, então nenhuma escrita acontece.

O acesso não é atômico. São dois acessos independentes à memória, e um observador externo pode ver a primeira metade já escrita antes da segunda.

## 5. Load Que Cruza a Palavra

A memória síncrona entrega o dado um ciclo depois de receber o endereço. Por isso as duas metades de um load chegam em estágios diferentes.

| Ciclo | Estágio da instrução | O que acontece |
| :--- | :--- | :--- |
| 1 | MEM, etapa 1 | A palavra do primeiro byte é pedida e o pipeline espera |
| 2 | MEM, etapa 2 | A palavra seguinte é pedida. O dado da etapa 1 chega e é guardado num registrador |
| 3 | WB | O dado da etapa 2 chega e é juntado ao dado guardado |

O registrador captura o dado da etapa 1 somente no primeiro ciclo da etapa 2, mesmo que a etapa 2 fique retida por uma parada de EX, para não perder a primeira palavra. No estágio WB as duas palavras formam um par de 64 bits, com a palavra recém-chegada na metade alta. O par é deslocado à direita de $8o$ bits, e a palavra baixa do resultado é o dado do load alinhado ao byte 0.

$$
\text{par} = \text{palavra}_{2} \mathbin{\|} \text{palavra}_{1} \qquad \text{dado} = (\text{par} \gg 8o)[31:0]
$$

Essa palavra segue para o extensor de loads com deslocamento zero, que aplica a extensão de sinal ou de zero conforme a instrução (`LW`, `LH` ou `LHU`).

Para `LW` com $o = 1$, os bytes do resultado vêm da palavra 1 (bytes 1, 2 e 3) e da palavra 2 (byte 0), do menos para o mais significativo.

## 6. Resumo do Caminho no Pipeline

| Estágio | Papel no acesso desalinhado |
| :--- | :--- |
| EX | Calcula o endereço efetivo e posiciona o dado do store. Sem Zicsr, também detecta o acesso que o hardware não executa |
| MEM | Com Zicsr, detecta o acesso que o hardware não executa e o anula antes de tocar a memória. Divide o acesso que cruza a palavra em duas etapas, escolhe o endereço, o dado e a máscara de cada etapa, e para o pipeline na etapa 1 |
| WB | Junta as duas palavras de um load que cruzou, alinha o resultado e o estende |

Um acesso que cruza a palavra custa um ciclo a mais na RAM interna. Nas regiões externas o custo cresce com a espera de cada etapa, pois cada uma depende do sinal de pronto do escravo.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
