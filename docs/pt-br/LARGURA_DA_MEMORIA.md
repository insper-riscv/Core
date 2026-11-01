# Memória com Largura Diferente da Palavra da CPU

O Core fala com a memória de dados em palavras de 32 bits, acompanhadas de uma máscara de 4 bits com um bit por byte. Quando o dispositivo de memória tem outra largura, um adaptador entre os dois reconcilia a diferença. Este documento descreve as regras que o adaptador precisa cumprir e as formas de montá-lo.

## 1. O Que a CPU Espera

| Propriedade | Valor |
| :--- | :--- |
| Dado | 32 bits, com os bytes nas posições do endereço (little-endian) |
| Máscara de escrita | 4 bits, um por byte, `0` em loads |
| Endereço | Endereço de byte, com os dois bits baixos indicando a posição dentro da palavra |
| Leitura | Palavra de 32 bits inteira, sem máscara. A seleção de byte ou meia palavra e a extensão de sinal acontecem no estágio WB |

O adaptador nunca recebe a largura da instrução. Ele só vê a máscara de bytes na escrita e uma palavra inteira na leitura.

Os dois caminhos de dados do Core têm contratos de tempo diferentes, e isso decide onde a memória pode ficar.

| Caminho | Faixa | Espera |
| :--- | :--- | :--- |
| RAM interna | `0x00008000` a `0x3FFFFFFF` | Nenhuma. A resposta chega sempre um ciclo depois do endereço |
| Barramento externo | `0x40000000` em diante | Pelo sinal de pronto, de duração variável |

No mapa com FLASH externa, escolhido pelo parâmetro `ext_flash`, não há RAM interna, e a FLASH em `0x20000000` também responde pelo barramento externo.

## 2. Relação Entre as Larguras

Seja $W$ a largura do dispositivo em bits. Duas grandezas descrevem a adaptação.

| Caso | Condição | Grandeza | Expressão |
| :--- | :--- | :--- | :--- |
| Estreita | $W < 32$ | Fatias por palavra | $n = 32 / W$ |
| Larga | $W > 32$ | Palavras de CPU por palavra da memória | $m = W / 32$ |

Na memória estreita, uma palavra da CPU ocupa $n$ posições do dispositivo. Na memória larga, uma palavra do dispositivo contém $m$ palavras da CPU, e o endereço escolhe qual delas.

## 3. Memória Mais Estreita que a CPU

Há duas formas de montar uma palavra de 32 bits com dispositivos estreitos.

| Forma | Como funciona | Ciclos por acesso | Onde pode ficar |
| :--- | :--- | :--- | :--- |
| Dispositivos em paralelo | $n$ dispositivos lado a lado, cada um com a sua fatia do dado e da máscara, mesmo endereço | Os mesmos de um dispositivo de 32 bits | RAM interna ou barramento externo |
| Um dispositivo, em série | Um único dispositivo recebe as $n$ fatias em sequência | $n$ ou mais | Só o barramento externo |

A forma em série precisa de espera, e a RAM interna não tem sinal de pronto. Um dispositivo estreito único, como o chip de SDRAM, pertence portanto à janela do barramento externo.

### 3.1. Endereço

O adaptador descarta os dois bits baixos do endereço de byte e trabalha com o índice de palavra. Esse índice, multiplicado por $n$, dá a posição da primeira fatia no dispositivo.

### 3.2. Escrita

Cada fatia recebe o seu trecho do dado e o seu trecho da máscara. Para a fatia $k$, com $k = 0$ a menos significativa, os bits do dado e da máscara são os seguintes.

$$
\text{dado}_k = \text{dado}[W(k+1)-1 : Wk] \qquad \text{máscara}_k = \text{máscara}\left[\tfrac{W}{8}(k+1)-1 : \tfrac{W}{8}k\right]
$$

Uma fatia com máscara toda em zero não precisa ser escrita. Dispositivos cuja máscara é ativa em nível baixo, como o chip de SDRAM, recebem a máscara invertida.

Exemplo com $W = 16$ e $n = 2$, para um `SH` no deslocamento 2 de uma palavra, com máscara `1100`.

| Fatia | Bits do dado | Máscara da fatia | Máscara no chip (ativa em baixo) | Efeito |
| :--- | :--- | :--- | :--- | :--- |
| 0 | `[15:0]` | `00` | `11` | Nada é escrito |
| 1 | `[31:16]` | `11` | `00` | Os dois bytes são escritos |

### 3.3. Leitura

As $n$ fatias são lidas em sequência e concatenadas, com a fatia 0 nos bits baixos. A palavra só vale quando a última fatia chega.

$$
\text{palavra} = \text{fatia}_{n-1} \mathbin{\|} \dots \mathbin{\|} \text{fatia}_1 \mathbin{\|} \text{fatia}_0
$$

A palavra inteira volta à CPU mesmo quando o load pede um byte, porque a seleção do byte acontece no estágio WB.

### 3.4. Sinal de pronto

Enquanto as fatias não terminam, o adaptador mantém o sinal de pronto em zero, e a CPU segura o estágio MEM. As regras do barramento externo valem para o adaptador.

1. O endereço, o dado, a máscara e os pedidos de leitura e escrita ficam estáveis até o pronto subir.
2. O sinal de pronto é um nível. Ele fica em `1` até o adaptador observar que o pipeline avançou.
3. O dado lido não muda enquanto a instrução de load ainda está no estágio WB. O adaptador só troca o dado de leitura na borda em que o pipeline avança.

## 4. Memória Mais Larga que a CPU

Com $m$ palavras de CPU em cada palavra do dispositivo, o adaptador usa os bits de endereço logo acima dos dois bits baixos para escolher a faixa de 32 bits.

$$
\text{faixa} = \text{endereço}\left[\log_2 m + 1 : 2\right]
$$

### 4.1. Leitura

O dispositivo entrega a palavra larga, e o adaptador devolve só a faixa escolhida, sem deslocá-la. O deslocamento por byte continua a cargo do estágio WB.

### 4.2. Escrita

O adaptador coloca o dado de 32 bits na faixa escolhida e monta uma máscara de $W/8$ bits com apenas os 4 bits dessa faixa copiados da máscara da CPU. Os demais bytes ficam desabilitados e não são alterados.

| Dispositivo | Máscara da CPU | Faixa | Máscara no dispositivo |
| :--- | :--- | :--- | :--- |
| 64 bits ($m = 2$) | `0011` | 0 | `0000 0011` |
| 64 bits ($m = 2$) | `0011` | 1 | `0011 0000` |
| 128 bits ($m = 4$) | `1111` | 2 | `0000 1111 0000 0000` |

Se o dispositivo não tem máscara de bytes, a escrita parcial exige leitura, mistura e escrita. O adaptador lê a palavra larga, troca os bytes habilitados e grava a palavra inteira. Esse acesso ocupa vários ciclos e só pode ficar no barramento externo, pelo mesmo motivo da seção 3.

### 4.3. Aproveitar a largura

Uma palavra larga permite transferir várias palavras de CPU de uma vez. A cache de dados usa isso, com linhas de 16 bytes (quatro palavras) movidas por um único pedido ao controlador da SDRAM. O pedido de linha leva as palavras 1 a 3 em portas extras de 32 bits cada, ao lado da porta de uma palavra. Com $W = 128$, uma linha cabe numa única palavra do dispositivo.

## 5. Interação com o Acesso Desalinhado

Um acesso que cruza a palavra chega ao adaptador como dois acessos independentes, cada um com o endereço de uma palavra de CPU alinhada. A unidade de acesso desalinhado do Core apresenta o endereço da palavra seguinte na segunda etapa, e o adaptador trata cada etapa como um acesso comum.

Essa regra tem duas consequências.

- O adaptador não pode supor que as duas palavras estão na mesma palavra do dispositivo. Numa memória larga elas podem estar, mas num limite entre palavras largas ficam em palavras diferentes.
- O primeiro endereço da instrução chega com os dois bits baixos preenchidos, e o adaptador os descarta.

## 6. Resumo das Decisões

| Pergunta | Resposta |
| :--- | :--- |
| A memória tem $W < 32$ e um só dispositivo | Serializar em $n$ fatias, usar o barramento externo e o sinal de pronto |
| A memória tem $W < 32$ e $n$ dispositivos | Colocar em paralelo, sem custo de ciclo, com a fatia da máscara em cada um |
| A memória tem $W > 32$ | Selecionar a faixa pelo endereço e replicar o dado na escrita |
| A memória não tem máscara de bytes | Ler, misturar e escrever, no barramento externo |
| O dispositivo precisa de mais de um ciclo | Barramento externo, nunca a RAM interna |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../LICENSE).
