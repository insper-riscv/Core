# Desvio tomado apagado pelo flush com o pipeline parado

## 1. Resumo

Quando o estágio MEM espera uma memória de latência variável (a SDRAM), o
pipeline inteiro fica parado. Um desvio tomado que estivesse em EX nesse
momento era apagado pelo flush antes de chegar a MEM, e o PC não era
redirecionado. Depois da espera, o core seguia sequencialmente e executava as
instruções do caminho errado.

| | |
| :--- | :--- |
| Sintoma | Laço ou salto logo depois de um load da SDRAM segue o caminho errado, só quando a espera é maior que zero ciclos |
| Condição | Desvio ou salto tomado em EX no mesmo ciclo em que o MEM espera um acesso à SDRAM |
| Correção | O flush só vale quando o pipeline anda |
| Teste | Teste de entidade do core com uma SDRAM de latência variável, em que o desvio pula três instruções |

## 2. Como o pipeline trata um desvio tomado

O desvio é resolvido em EX. No ciclo em que ele é resolvido, na mesma borda de
clock:

| Registrador | O que acontece na borda |
| :--- | :--- |
| EX/MEM | captura o resultado do desvio e o leva adiante |
| ID/EX e IF/ID | recebem flush: as instruções do caminho errado que já foram buscadas são descartadas |
| PC | recebe o endereço de destino |

O registrador ID/EX guarda a instrução que está em EX. O flush dele não perde o
desvio porque, na mesma borda, o EX/MEM já o capturou.

## 3. O que dava errado com o pipeline parado

Quando um acesso à SDRAM está em MEM e ainda não terminou, o pipeline pára: os
registradores ID/EX, EX/MEM e MEM/WB e o PC ficam com o enable em zero. Se um
desvio tomado estiver em EX nessa hora:

1. O EX/MEM não captura o desvio, porque está parado.
2. O PC não é atualizado, porque está parado.
3. O flush não depende do enable: em ID/EX e IF/ID a condição de flush é testada antes do enable. Como o desvio continua em EX, a condição de flush continua verdadeira em todos os ciclos da espera.
4. O ID/EX é esvaziado a cada ciclo de espera, e com ele o próprio desvio.

Quando o acesso termina, o desvio já não existe em nenhum estágio, e o PC
continua de onde estava. Exemplo, com o desvio no endereço $A$ e o destino em
$A + 16$:

| Momento | PC (busca) | ID | EX | O que se perde |
| :--- | :--- | :--- | :--- | :--- |
| Antes da espera | $A + 8$ | $A + 4$ | desvio ($A$) | nada |
| Durante a espera | $A + 8$ | vazio | vazio | o desvio |
| Depois da espera | $A + 8$, $A + 12$, ... | instruções sequenciais | caminho errado | o redirecionamento para $A + 16$ |

O erro só aparece se o destino for diferente do endereço que o PC já estava
buscando. Um desvio que pula uma única instrução cai exatamente em $A + 8$ e
parece correto por coincidência.

## 4. Quando acontece

Precisa das duas condições ao mesmo tempo:

- um load ou store da SDRAM em MEM, com a memória ainda não pronta;
- um desvio ou salto tomado em EX no mesmo ciclo.

O padrão mais comum é um laço em C: um load da SDRAM seguido do desvio de volta
ao início do laço. Com espera de zero ciclos o bug não aparece, e por isso ele
só aparece com uma memória que demora.

## 5. A correção

O flush passa a valer só quando o pipeline anda, isto é, quando nem o muldiv
nem a SDRAM estão parando:

$$
\text{flush} = (\text{desvio tomado} \lor \text{salto tomado}) \land \text{pipeline anda}
$$

Com o pipeline parado, o desvio fica em EX sem flush. Quando o pipeline volta a
andar, o desvio é capturado pelo EX/MEM e o flush e o redirecionamento do PC
acontecem juntos, como no caso sem espera. Com o muldiv a condição é
equivalente à anterior, porque o muldiv ocupa o estágio EX e um desvio não pode
estar ali ao mesmo tempo.

## 6. Como o teste prova a correção

O teste de entidade roda o core contra uma SDRAM simulada que responde depois de
0 a 9 ciclos de espera. O programa executa um load da SDRAM e, logo em seguida,
um desvio tomado que pula **três** instruções.

| Versão do core | Resultado |
| :--- | :--- |
| Com a correção | passa em todas as latências |
| Sem a correção | falha: o registrador usado pelas instruções puladas vale 255 em vez de 1 |

O desvio precisa pular mais de uma instrução. Com uma só, o destino coincide
com o endereço que o PC já estava buscando e o erro fica escondido, como na
seção 3.
