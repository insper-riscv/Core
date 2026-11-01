# Acesso Desalinhado à Memória (Zicclsm)

A extensão Zicclsm exige que loads e stores com endereço desalinhado funcionem em hardware, em vez de gerarem exceção. Este documento descreve como o Core executa esses acessos e qual é o caminho de uma instrução desalinhada pelo pipeline. O parâmetro `has_zicclsm` liga e desliga a extensão.

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

A extensão cobre apenas a memória principal. Os intervalos de endereço vêm do mapa de memória do Core, que tem duas formas, escolhidas pelo parâmetro `ext_flash`.

No mapa padrão a memória principal é a RAM interna e a janela de SDRAM.

| Região | Faixa | Acesso desalinhado em hardware |
| :--- | :--- | :--- |
| BOOT_ROM e FLASH interna | abaixo de `0x00008000` | Não, gera exceção |
| RAM interna | `0x00008000` até `0x3FFFFFFF` | Sim |
| SDRAM | `0x40000000` até `0x7FFFFFFF` | Sim |
| Periféricos | `0x80000000` em diante | Não, gera exceção |

No mapa com FLASH externa não há RAM interna, e a memória principal é a FLASH, que fica atrás das caches, e a janela de SDRAM.

| Região | Faixa | Acesso desalinhado em hardware |
| :--- | :--- | :--- |
| BOOT_ROM e faixa sem memória | abaixo de `0x20000000` | Não, gera exceção |
| FLASH externa | `0x20000000` até `0x3FFFFFFF` | Sim |
| SDRAM | `0x40000000` até `0x7FFFFFFF` | Sim |
| Periféricos | `0x80000000` em diante | Não, gera exceção |

A decisão é tomada no estágio EX, antes de a instrução chegar à memória. Um acesso que cruza a palavra só é executado quando atende às três condições abaixo.

1. O endereço está na memória principal do mapa em uso.
2. As duas palavras estão na mesma região. A última palavra de cada região é rejeitada, porque a palavra seguinte pertence à região vizinha.
3. A palavra seguinte existe, ou seja, o endereço não é a última palavra do espaço de 32 bits.

Quando alguma condição falha, ou quando `has_zicclsm` é falso, a instrução é anulada em EX antes de alcançar o estágio MEM. Com Zicsr ativo, a exceção usa `mcause = 4` para load e `mcause = 6` para store, e `mtval` recebe o endereço efetivo. Sem Zicsr, a exceção é só sinalizada nas saídas do Core. O Core recusa a elaboração com `has_zicclsm` falso e sem Zicsr, porque nada trataria o acesso.

## 3. Acesso Que Cruza a Palavra

Um acesso que cruza a palavra roda em duas etapas, ambas no estágio MEM.

| Etapa | Endereço apresentado | Dado e máscara de store | Pipeline |
| :--- | :--- | :--- | :--- |
| 1 | Palavra do primeiro byte | Bytes que cabem nessa palavra | Parado até a etapa concluir |
| 2 | Palavra seguinte, $\text{palavra} + 4$ | Bytes restantes | Avança normalmente |

Um flip-flop indica a etapa corrente. Ele passa a `1` quando a etapa 1 conclui e volta a `0` quando a instrução deixa o estágio MEM.

A etapa 1 conclui quando duas condições valem no mesmo ciclo.

- O escravo está pronto. A RAM interna sempre está, pois responde em um ciclo. A SDRAM, e a FLASH externa no mapa com FLASH externa, só estão quando o sinal de pronto chega.
- A memória pode avançar, isto é, o pipeline não está parado por multiplicação ou divisão nem por espera de SDRAM.

Durante a etapa 1 o sinal de parada da unidade congela os estágios anteriores e mantém a instrução em MEM. Na etapa 2 esse sinal desce, e a instrução sai de MEM quando o pipeline avança, como um acesso alinhado.

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

O acesso não é atômico. A primeira metade já pode estar escrita quando a segunda falha ou é interrompida.

## 5. Load Que Cruza a Palavra

A memória síncrona entrega o dado um ciclo depois de receber o endereço. Por isso as duas metades de um load chegam em estágios diferentes.

| Ciclo | Estágio da instrução | O que acontece |
| :--- | :--- | :--- |
| 1 | MEM, etapa 1 | A palavra do primeiro byte é pedida e o pipeline espera |
| 2 | MEM, etapa 2 | A palavra seguinte é pedida. O dado da etapa 1 chega e é guardado num registrador |
| 3 | WB | O dado da etapa 2 chega e é juntado ao dado guardado |

No estágio WB as duas palavras formam um par de 64 bits, com a palavra recém-chegada na metade alta. O par é deslocado à direita de $8o$ bits, e a palavra baixa do resultado é o dado do load alinhado ao byte 0.

$$
\text{par} = \text{palavra}_{2} \mathbin{\|} \text{palavra}_{1} \qquad \text{dado} = (\text{par} \gg 8o)[31:0]
$$

Essa palavra segue para o extensor de loads com deslocamento zero, que aplica a extensão de sinal ou de zero conforme a instrução (`LW`, `LH` ou `LHU`).

Para `LW` com $o = 1$, os bytes do resultado vêm da palavra 1 (bytes 1, 2 e 3) e da palavra 2 (byte 0), do menos para o mais significativo.

## 6. Resumo do Caminho no Pipeline

| Estágio | Papel no acesso desalinhado |
| :--- | :--- |
| EX | Detecta o desalinhamento, decide entre executar em hardware e gerar exceção, e posiciona o dado do store |
| MEM | Divide o acesso que cruza a palavra em duas etapas, escolhe o endereço, o dado e a máscara de cada etapa, e para o pipeline na etapa 1 |
| WB | Junta as duas palavras de um load que cruzou, alinha o resultado e o estende |

Um acesso que cruza a palavra custa um ciclo a mais na RAM interna. Na SDRAM e na FLASH externa o custo cresce com a espera de cada etapa, pois cada uma depende do sinal de pronto do escravo.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../LICENSE).
