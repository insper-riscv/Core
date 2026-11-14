# Zicclsm: Implementação no Core

A Zicclsm é a extensão, definida na especificação de perfis do RISC-V, que exige loads e stores desalinhados executados sem exceção na memória principal. Este documento descreve como o Core executa esses acessos e qual é o caminho de uma instrução desalinhada pelo pipeline. O que a especificação exige, com as fontes, está em [instructions.md](instructions.md). O constante `HAS_ZICCLSM` (padrão `true`) liga e desliga a extensão.

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

Para efeito da extensão, o Core trata como memória principal tudo o que não é a Memória de boot nem a FLASH direta, que são só de leitura e não repartem um acesso em duas leituras. Os limites vêm das constantes do mapa de memória do `config_pkg` (`BOOT_MEMORY_END`, `FLASH_BASE`, `FLASH_END`, `FLASH_ON_BUS`, `RAM_BASE`, `RAM_END` e `RAM_ON_BUS`), descritos em [02-barramento-e-memoria.md](../../contracts/02-barramento-e-memoria.md). Os intervalos abaixo são semiabertos e valem para qualquer valor das constantes.

| Região | Faixa em função das constantes | Acesso desalinhado em hardware |
| :--- | :--- | :--- |
| Memória de boot | `[0, BOOT_MEMORY_END)` | Não, gera exceção |
| FLASH com `FLASH_ON_BUS` falso | `[FLASH_BASE, FLASH_END)` | Não, gera exceção |
| FLASH com `FLASH_ON_BUS` verdadeiro | `[FLASH_BASE, FLASH_END)` | Sim |
| RAM, direta ou no barramento | `[RAM_BASE, RAM_END)` | Sim |
| Fora das três regiões (barramento) | O restante de `[0, 2**ADDR_BITS)` | Sim |

Cada plataforma fixa as constantes no seu `platform.yaml`. No mapa padrão (`FLASH_END = 0x00008000`, `RAM_END = 0x40000000`, as duas memórias diretas), a memória principal começa em `0x00008000`, e o que está acima de `RAM_END` sai pela porta externa, que responde erro se nenhum escravo atende o endereço. Com a FLASH no barramento, a memória principal passa a incluir a FLASH, e começa logo depois da Memória de boot.

Um acesso desalinhado que cabe numa palavra (`LH`, `LHU` e `SH` com $o = 1$) é executado quando o endereço está na memória principal. Um acesso que cruza a palavra é executado apenas quando atende às duas condições abaixo.

1. O endereço está na memória principal do mapa em uso.
2. O endereço não pertence à última palavra de uma região de caminho próprio, nem ao topo do espaço de endereços. As duas palavras do acesso precisam ficar na mesma região, e a palavra seguinte à última de cada região (`FLASH_END`, `RAM_END`) pertence à região vizinha, mesmo quando os endereços são contíguos (por exemplo, `0x3FFFFFFC` no mapa padrão).

Quando alguma condição falha, ou quando `HAS_ZICCLSM` é falso, o acesso gera exceção de endereço desalinhado. A instrução é anulada antes de acessar a memória, o que ocorre no estágio MEM quando o Core tem Zicsr e no estágio EX quando não tem. Com Zicsr ativo, a exceção usa `mcause = 4` para load e `mcause = 6` para store, e `mtval` recebe o endereço efetivo. Sem Zicsr, a exceção é só sinalizada nas saídas do Core, como descrito em [02-barramento-e-memoria.md](../../contracts/02-barramento-e-memoria.md). A combinação sem Zicsr e sem Zicclsm é uma configuração válida.

## 3. Acesso Que Cruza a Palavra

Um acesso que cruza a palavra roda em duas etapas, ambas no estágio MEM.

| Etapa | Endereço apresentado | Dado e máscara de store | Pipeline |
| :--- | :--- | :--- | :--- |
| 1 | Palavra do primeiro byte | Bytes que cabem nessa palavra | Parado até a etapa concluir |
| 2 | Palavra seguinte, $\text{palavra} + 4$ | Bytes restantes | Avança normalmente |

Um flip-flop indica a etapa corrente. Ele passa a `1` quando a etapa 1 conclui e volta a `0` quando a instrução deixa o estágio MEM.

A etapa 1 conclui quando duas condições valem no mesmo ciclo.

- O escravo está pronto. A RAM interna sempre está, pois responde em um ciclo. As regiões no barramento (a FLASH e a RAM no barramento e tudo fora das três regiões) só estão quando o sinal de pronto chega.
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
