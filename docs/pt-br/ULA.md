# Unidade Lógica e Aritmética (ULA)

## 1. Visão geral

A ULA executa em um único estágio (EX), de forma combinacional, todas as operações inteiras da base RV32I, o cálculo do endereço-alvo de `JALR`, a carga de imediato de `LUI` e a avaliação dos seis desvios condicionais. O resultado de dados sai em `o_d`, e a condição de desvio sai em `o_branch`.

A organização segue uma regra: o código da operação já é a decisão de hardware. Ele tem a mesma estrutura do campo `funct3` das instruções, de modo que a ULA escolhe o resultado direto dos bits do código, sem recodificação, e o decodificador do estágio ID entrega o código pronto. Um único somador-subtrator atende todas as operações que dependem de uma soma ou de uma comparação de magnitude.

## 2. Código da operação

O código `alu_op_t` tem 5 bits, que se dividem em três campos.

| Bits | Nome | Significado |
| :--- | :--- | :--- |
| 4 | Classe de controle | `1` para `JALR`, `LUI` e os seis desvios |
| 3 | Inversão | `1` inverte o operando B e soma 1 (subtração e comparações); nos deslocamentos à direita, `1` seleciona o deslocamento aritmético |
| 2 a 0 | Seleção do resultado | O `funct3` das instruções de tipo R e I; nos desvios, o `funct3` do desvio |

A seleção do resultado, nas operações fora da classe de controle, segue o `funct3` do RISC-V.

| Bits 2 a 0 | Resultado em `o_d` |
| :--- | :--- |
| `000` | Soma ou subtração |
| `001` | Deslocamento à esquerda |
| `010` | Menor-que com sinal |
| `011` | Menor-que sem sinal |
| `100` | OU exclusivo |
| `101` | Deslocamento à direita |
| `110` | OU |
| `111` | E |

## 3. Operações

| Constante | Código | `o_d` | `o_branch` |
| :--- | :--- | :--- | :--- |
| `ALU_ADD` | `00000` | `a + b` | `0` |
| `ALU_SLL` | `00001` | `a << b[4:0]` | `0` |
| `ALU_XOR` | `00100` | `a xor b` | `0` |
| `ALU_SRL` | `00101` | `a >> b[4:0]` lógico | `0` |
| `ALU_OR` | `00110` | `a or b` | `0` |
| `ALU_AND` | `00111` | `a and b` | `0` |
| `ALU_SUB` | `01000` | `a - b` | `0` |
| `ALU_SLT` | `01010` | `1` se `a < b` com sinal, senão `0` | `0` |
| `ALU_SLTU` | `01011` | `1` se `a < b` sem sinal, senão `0` | `0` |
| `ALU_SRA` | `01101` | `a >> b[4:0]` aritmético | `0` |
| `ALU_JALR` | `10000` | `(a + b)` com o bit 0 zerado | `0` |
| `ALU_LUI` | `10001` | `b` | `0` |
| `ALU_BEQ` | `11000` | `0` | `a = b` |
| `ALU_BNE` | `11001` | `0` | `a /= b` |
| `ALU_BLT` | `11100` | `0` | `a < b` com sinal |
| `ALU_BGE` | `11101` | `0` | `a >= b` com sinal |
| `ALU_BLTU` | `11110` | `0` | `a < b` sem sinal |
| `ALU_BGEU` | `11111` | `0` | `a >= b` sem sinal |

## 4. Somador-subtrator compartilhado

Com $inv$ igual ao bit 3 do código, o somador calcula

$$S = a_{\mathrm{eff}} + (b \oplus inv) + inv,$$

em 33 bits, para que o bit extra seja o carry de saída $c_{out}$. Com $inv = 0$ o resultado é $a + b$, e com $inv = 1$ é $a - b$ em complemento de dois. Esse mesmo $S$ serve a `ADD`, `SUB`, `JALR`, `LUI`, `SLT`, `SLTU` e às quatro comparações de magnitude dos desvios.

As comparações saem da subtração, sem outro comparador:

$$a <_u b = \lnot c_{out}$$

$$a <_s b = \begin{cases} a_{31} & \text{se } a_{31} \neq b_{31} \\ S_{31} & \text{caso contrário} \end{cases}$$

Quando os sinais diferem, o negativo é o menor. Quando coincidem, a subtração não estoura e seu sinal decide.

A igualdade dos desvios `BEQ` e `BNE` usa um comparador próprio entre $a$ e $b$, que não espera a cadeia de carry do somador.

## 5. Desvios

Nos seis desvios, o bit de classe e o de inversão valem `1`, e o campo de seleção é o `funct3` do desvio. A ULA zera `o_d` e avalia `o_branch` conforme a tabela.

| `funct3` do desvio | Desvio | `o_branch` |
| :--- | :--- | :--- |
| `000` | `BEQ` | igualdade |
| `001` | `BNE` | negação da igualdade |
| `100` | `BLT` | menor-que com sinal |
| `101` | `BGE` | negação do menor-que com sinal |
| `110` | `BLTU` | menor-que sem sinal |
| `111` | `BGEU` | negação do menor-que sem sinal |

O endereço-alvo do desvio é calculado por somadores próprios no estágio EX, e `o_branch` só decide se ele é tomado.

## 6. Deslocadores

Há um deslocador à esquerda e um à direita. O da direita recebe um bit de preenchimento à esquerda, que é o sinal de $a$ quando o bit de inversão é `1` (`SRA`) e zero quando é `0` (`SRL`). A quantidade de deslocamento são os 5 bits baixos de $b$.

Cada deslocador é uma cascata de multiplexadores 4 para 1, um por par de bits da quantidade: o primeiro desloca de 0 a 3 posições, o segundo de 0, 4, 8 ou 12 e o terceiro de 0 ou 16. Um multiplexador 4 para 1 cabe numa LUT de 6 entradas, então o deslocamento inteiro ocupa três níveis de lógica.

## 7. Seleção do resultado

O resultado de dados sai de um E-OU entre oito termos, cada um habilitado por um bit da seleção one-hot `i_res_sel`: soma, deslocamento à esquerda, menor-que com sinal, menor-que sem sinal, XOR, deslocamento à direita, OR e AND. O estágio ID decodifica o código de operação nessa seleção, que viaja pelo registrador ID/EX, de modo que a ULA não decodifica nada. JALR e LUI selecionam a soma, e os desvios não selecionam nenhum termo, o que zera o resultado de dados.

Os termos se dividem em dois grupos. O grupo rápido reúne XOR, OR, AND e os bits de menor-que, que só dependem de lógica bit a bit e dos comparadores. O grupo lento reúne a soma e os dois deslocamentos. Os dois grupos se juntam num último OR.

## 8. `LUI` e `JALR`

`LUI` pertence à classe de controle com a inversão em `0` e o bit 0 em `1`. A ULA força o operando A a zero e soma, então o resultado é o próprio imediato do operando B, sem uma fonte extra no multiplexador de resultado.

`JALR` pertence à classe de controle com a inversão em `0` e o bit 0 em `0`. O resultado é a soma com o bit 0 zerado, como o endereço de um salto indireto exige.

Nas duas operações, o campo de seleção do resultado é ignorado e a soma é sempre o resultado.

## 9. Verificação

| Teste | O que confere |
| :--- | :--- |
| `ALU` | Cada operação isoladamente (com a seleção one-hot que o ID geraria) e, para todas as 18, um modelo de referência em valores de borda (`0`, `1`, `31`, `32`, `0x7FFFFFFF`, `0x80000000`, `0xFFFFFFFF`) e 300 pares aleatórios |
| `control_unit` | O código que o decodificador gera para cada instrução, conforme a tabela de sinais de controle |
| Testes do core | Programas de instruções, traps, parada e `fence.i` que exercitam a ULA no pipeline |
