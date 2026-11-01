# Instrução FENCE.I (Zifencei)

A instrução `FENCE.I` sincroniza o fluxo de instruções com os stores anteriores do mesmo núcleo. Depois dela, uma busca de instrução enxerga tudo que o programa gravou na memória antes. Este documento descreve para que ela serve, como o Core a executa e o que acontece no pipeline e nas caches.

## 1. Para Que Serve

A busca de instruções e os stores usam caminhos diferentes. A cache de instruções só lê a memória e não observa os stores do núcleo. Um programa que grava código novo e salta para ele precisa, portanto, de um passo que torne a escrita visível à busca.

| Situação | Sem `FENCE.I` | Com `FENCE.I` |
| :--- | :--- | :--- |
| A cache de instruções guarda a linha antiga do endereço escrito | A busca executa o código antigo | A linha é descartada e a busca lê o código novo |
| Um store ainda está na cache de dados write-back | A memória não tem o código novo | O store é gravado na memória antes da invalidação |

Casos típicos são um carregador que copia um programa para a memória, a geração de código em tempo de execução e a troca de uma rotina em uso.

## 2. Onde a Instrução Tem Efeito

Só o código buscado pela cache de instruções é afetado. A BOOT_ROM é lida diretamente, e a RAM interna não é região de busca. As regiões que passam pela cache dependem do mapa de memória do Core, escolhido pelo parâmetro `ext_flash`.

No mapa padrão a FLASH é interna e lida diretamente, de modo que só o código gravado em SDRAM muda de resultado com o `FENCE.I`.

| Região de busca | Faixa | Passa pela cache de instruções |
| :--- | :--- | :--- |
| BOOT_ROM | `0x00000000` a `0x000007FF` | Não |
| FLASH interna | `0x00000800` a `0x3FFFFFFF` | Não |
| SDRAM | `0x40000000` em diante | Sim |

No mapa com FLASH externa a FLASH fica atrás das caches, e o `FENCE.I` vale para o código gravado em qualquer uma das duas regiões.

| Região de busca | Faixa | Passa pela cache de instruções |
| :--- | :--- | :--- |
| BOOT_ROM | `0x00000000` a `0x000007FF` | Não |
| FLASH externa | `0x20000000` a `0x3FFFFFFF` | Sim |
| SDRAM | `0x40000000` em diante | Sim |

## 3. Configuração

Dois parâmetros do Core decidem o comportamento.

| Parâmetro | Significado |
| :--- | :--- |
| `has_zifencei` | Liga a extensão. É ligado pelos perfis cujo nome inclui `zifencei` |
| `has_dcache` | Indica uma cache de dados write-back, que exige descarga antes da invalidação |

| `has_zifencei` | Comportamento do `FENCE.I` |
| :--- | :--- |
| Falso | Instrução ilegal, com exceção de causa 2 quando há Zicsr |
| Verdadeiro | Executa conforme as seções 4 e 5 |

A instrução `FENCE` comum, com `funct3 = 000`, não é tratada por esta unidade e se comporta como `NOP`.

## 4. Execução Sem Cache de Dados

Sem cache de dados write-back, os stores já estão na memória quando deixam o estágio MEM. O `FENCE.I` conclui no mesmo ciclo em que está válido no estágio EX e o pipeline avança. Nesse ciclo a unidade emite um pulso de conclusão, que produz os três efeitos abaixo.

1. Invalida a cache de instruções.
2. Descarta as instruções de IF/ID e ID/EX.
3. Redireciona o PC para $\text{PC} + 4$, o endereço da instrução seguinte ao `FENCE.I`.

## 5. Execução Com Cache de Dados Write-Back

Com a cache de dados, os stores anteriores podem estar apenas na cache. A unidade as descarrega antes de invalidar a cache de instruções, porque a invalidação só ajuda se a memória já tem o código novo.

A unidade segura a instrução em EX e usa dois flip-flops, um que arma o pulso de descarga e outro que espera a confirmação.

| Ciclo | Evento | Pipeline |
| :--- | :--- | :--- |
| 0 | O `FENCE.I` chega a EX. O store logo atrás dele ainda está em MEM | Parado |
| 1 | Os stores anteriores já chegaram à cache. A unidade emite o pulso de descarga | Parado, salvo confirmação no mesmo ciclo |
| 2 em diante | A unidade espera a confirmação da cache | Parado |
| Ciclo da confirmação | A confirmação chega e o pulso de conclusão sai | Avança |

A confirmação pode chegar no ciclo do pulso de descarga, para uma cache que responde combinacionalmente, ou em qualquer ciclo depois. O pulso de conclusão sai no ciclo em que a confirmação chega, e produz os mesmos três efeitos da seção 4.

## 6. Efeito no Pipeline

| Elemento | Efeito |
| :--- | :--- |
| PC | Salta para $\text{PC} + 4$ no ciclo do pulso de conclusão |
| IF/ID e ID/EX | Esvaziados, o que descarta as duas instruções já buscadas depois do `FENCE.I` |
| EX/MEM | Recebe bolha enquanto a unidade segura a instrução, para a instrução não avançar duas vezes |
| Estágios anteriores | Congelados enquanto a unidade está ocupada |
| Saída para a cache de instruções | Pulso de invalidação de um ciclo, no ciclo do pulso de conclusão |
| Saída para a cache de dados | Pulso de descarga de um ciclo, só com `has_dcache` |

As duas instruções descartadas são buscadas de novo a partir de $\text{PC} + 4$, já com a cache de instruções vazia.

## 7. Efeito nas Caches

| Cache | Operação | Resultado |
| :--- | :--- | :--- |
| Instruções | Um pulso de invalidação | Todas as linhas são descartadas em um ciclo. Uma linha que ainda está sendo trazida da SDRAM no momento do pulso também é descartada, pois pode conter código anterior aos stores do programa |
| Dados write-back | Um pedido de descarga | Toda linha suja é gravada na memória. As linhas continuam válidas e passam a limpas |
| Dados com escrita direta | Um pedido de descarga | A memória já tem cada store concluído e nenhuma linha fica suja, então a descarga não grava nada |

A descarga percorre as 256 linhas da cache, com três ciclos para cada linha limpa, e acrescenta o tempo de gravação de cada linha suja. A cache de dados avisa a conclusão com um pulso, que o Core usa como confirmação.

## 8. Uso no Programa

A sequência correta grava o código, executa o `FENCE.I` e só então salta para ele.

```asm
    sw      t1, 0(t0)       # grava a nova instrução em t0
    fence.i                 # torna a escrita visível à busca
    jr      t0              # executa o código novo
```

Uma instrução entre o store e o `FENCE.I` não altera a garantia. O salto precisa vir depois do `FENCE.I`, porque só depois dele a busca vê o código novo.

## 9. Custo

| Configuração | Custo do `FENCE.I` |
| :--- | :--- |
| Sem cache de dados | Duas instruções descartadas, mais a falha de cache na primeira busca de SDRAM depois da invalidação |
| Com cache de dados | Cerca de 768 ciclos de varredura das 256 linhas, mais a gravação de cada linha suja, mais o custo anterior |

O custo da varredura existe mesmo sem linhas sujas, de modo que o `FENCE.I` é uma instrução cara com cache de dados e deve ser usado com pouca frequência.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../LICENSE).
