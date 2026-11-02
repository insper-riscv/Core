# RV32I: Requisitos da ISA e Comportamento do Core

Capítulo 1 do manual ([RV32I Base Integer Instruction Set](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)).

Este documento reúne o que o manual do RISC-V exige da base inteira RV32I e, em cada ponto, o que o Core faz. A fonte é o manual de ISA não privilegiada, versão 20260120, Capítulo 1 ("RV32I Base Integer Instruction Set, Version 2.1"), seção 1.1 e subseções. As codificações conferem com a listagem de instruções do Capítulo 35 do mesmo manual. O texto parafraseia o manual; ele não o substitui. A implementação em hardware está em [description.md](description.md).

## 1. Estado do Programador

Seção 1.1.1 do manual.

| Elemento | Largura | Regra do manual |
| :--- | :--- | :--- |
| `x0` | 32 bits | Fixo em zero; leituras devolvem 0 e escritas não têm efeito |
| `x1` a `x31` | 32 bits | Registradores de uso geral |
| `pc` | 32 bits | Endereço da instrução em execução; é o único outro registrador não privilegiado |

O manual não define ponteiro de pilha nem registrador de retorno; a convenção usa `x1` como endereço de retorno, `x5` como registrador de ligação alternativo e `x2` como ponteiro de pilha. A variante RV32E reduz o banco a 16 registradores (Capítulo 2 do manual) e é tratada em [RV32E.md](../../RV32E.md).

No Core, `x0` não ocupa flip-flop. O banco armazena apenas `x1` a `x31`, e a porta de leitura do endereço 0 devolve a constante zero. Uma escrita com destino `x0` é descartada, e o adiantamento de dados ignora qualquer instrução cujo destino seja `x0`.

## 2. Formatos de Instrução

Seções 1.1.2 e 1.1.3 do manual. Todas as instruções têm 32 bits, e os campos `rs1`, `rs2` e `rd` ocupam as mesmas posições em todos os formatos. O bit de sinal de todo imediato é o bit 31 da instrução.

| Formato | Campos (do bit 31 ao bit 0) | Imediato produzido |
| :--- | :--- | :--- |
| R | `funct7` `rs2` `rs1` `funct3` `rd` `opcode` | Nenhum |
| I | `imm[11:0]` `rs1` `funct3` `rd` `opcode` | $\text{sext}(\text{inst}[31:20])$ |
| S | `imm[11:5]` `rs2` `rs1` `funct3` `imm[4:0]` `opcode` | $\text{sext}(\text{inst}[31:25] \,\Vert\, \text{inst}[11:7])$ |
| B | `imm[12\|10:5]` `rs2` `rs1` `funct3` `imm[4:1\|11]` `opcode` | Deslocamento de 13 bits, múltiplo de 2 |
| U | `imm[31:12]` `rd` `opcode` | $\text{inst}[31:12] \ll 12$ |
| J | `imm[20\|10:1\|11\|19:12]` `rd` `opcode` | Deslocamento de 21 bits, múltiplo de 2 |

O manual rearranja os bits dos imediatos B e J para que a maioria deles coincida com os formatos S e I, o que reduz a multiplexação no hardware. Os deslocamentos de B e J são sempre múltiplos de 2 porque o bit 0 do imediato é zero.

## 3. As 37 Instruções da Base

A base RV32I tem 40 instruções segundo o manual (seção 1.1). As 37 abaixo operam sobre registradores e memória; `FENCE`, `ECALL` e `EBREAK` completam as 40 e estão na seção 5. Nenhuma instrução inteira computacional gera exceção aritmética (seção 1.1.4).

Convenções da tabela: `sext` estende com sinal, `zext` estende com zero, `<s` e `<u` comparam com e sem sinal, `>>u` e `>>s` deslocam de forma lógica e aritmética, e `ea` é o endereço efetivo $x[rs1] + \text{sext}(\text{off})$. O `shamt` é `inst[24:20]`.

| Instrução | Formato | `opcode` | `funct3` | `funct7` | Semântica | Seção do manual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `LUI` | U | `0110111` | - | - | `x[rd] = imm << 12` | 1.1.4.1 |
| `AUIPC` | U | `0010111` | - | - | `x[rd] = pc + (imm << 12)` | 1.1.4.1 |
| `JAL` | J | `1101111` | - | - | `x[rd] = pc + 4; pc = pc + sext(off)` | 1.1.5.1 |
| `JALR` | I | `1100111` | `000` | - | `t = pc + 4; pc = (x[rs1] + sext(off)) & ~1; x[rd] = t` | 1.1.5.1 |
| `BEQ` | B | `1100011` | `000` | - | `if (x[rs1] == x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BNE` | B | `1100011` | `001` | - | `if (x[rs1] != x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BLT` | B | `1100011` | `100` | - | `if (x[rs1] <s x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BGE` | B | `1100011` | `101` | - | `if (x[rs1] >=s x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BLTU` | B | `1100011` | `110` | - | `if (x[rs1] <u x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `BGEU` | B | `1100011` | `111` | - | `if (x[rs1] >=u x[rs2]) pc = pc + sext(off)` | 1.1.5.2 |
| `LB` | I | `0000011` | `000` | - | `x[rd] = sext(M[ea][7:0])` | 1.1.6 |
| `LH` | I | `0000011` | `001` | - | `x[rd] = sext(M[ea][15:0])` | 1.1.6 |
| `LW` | I | `0000011` | `010` | - | `x[rd] = M[ea][31:0]` | 1.1.6 |
| `LBU` | I | `0000011` | `100` | - | `x[rd] = zext(M[ea][7:0])` | 1.1.6 |
| `LHU` | I | `0000011` | `101` | - | `x[rd] = zext(M[ea][15:0])` | 1.1.6 |
| `SB` | S | `0100011` | `000` | - | `M[ea] = x[rs2][7:0]` | 1.1.6 |
| `SH` | S | `0100011` | `001` | - | `M[ea] = x[rs2][15:0]` | 1.1.6 |
| `SW` | S | `0100011` | `010` | - | `M[ea] = x[rs2][31:0]` | 1.1.6 |
| `ADDI` | I | `0010011` | `000` | - | `x[rd] = x[rs1] + sext(imm)` | 1.1.4.1 |
| `SLTI` | I | `0010011` | `010` | - | `x[rd] = (x[rs1] <s sext(imm)) ? 1 : 0` | 1.1.4.1 |
| `SLTIU` | I | `0010011` | `011` | - | `x[rd] = (x[rs1] <u sext(imm)) ? 1 : 0` | 1.1.4.1 |
| `XORI` | I | `0010011` | `100` | - | `x[rd] = x[rs1] ^ sext(imm)` | 1.1.4.1 |
| `ORI` | I | `0010011` | `110` | - | `x[rd] = x[rs1] \| sext(imm)` | 1.1.4.1 |
| `ANDI` | I | `0010011` | `111` | - | `x[rd] = x[rs1] & sext(imm)` | 1.1.4.1 |
| `SLLI` | I | `0010011` | `001` | `0000000` | `x[rd] = x[rs1] << shamt` | 1.1.4.1 |
| `SRLI` | I | `0010011` | `101` | `0000000` | `x[rd] = x[rs1] >>u shamt` | 1.1.4.1 |
| `SRAI` | I | `0010011` | `101` | `0100000` | `x[rd] = x[rs1] >>s shamt` | 1.1.4.1 |
| `ADD` | R | `0110011` | `000` | `0000000` | `x[rd] = x[rs1] + x[rs2]` | 1.1.4.2 |
| `SUB` | R | `0110011` | `000` | `0100000` | `x[rd] = x[rs1] - x[rs2]` | 1.1.4.2 |
| `SLL` | R | `0110011` | `001` | `0000000` | `x[rd] = x[rs1] << x[rs2][4:0]` | 1.1.4.2 |
| `SLT` | R | `0110011` | `010` | `0000000` | `x[rd] = (x[rs1] <s x[rs2]) ? 1 : 0` | 1.1.4.2 |
| `SLTU` | R | `0110011` | `011` | `0000000` | `x[rd] = (x[rs1] <u x[rs2]) ? 1 : 0` | 1.1.4.2 |
| `XOR` | R | `0110011` | `100` | `0000000` | `x[rd] = x[rs1] ^ x[rs2]` | 1.1.4.2 |
| `SRL` | R | `0110011` | `101` | `0000000` | `x[rd] = x[rs1] >>u x[rs2][4:0]` | 1.1.4.2 |
| `SRA` | R | `0110011` | `101` | `0100000` | `x[rd] = x[rs1] >>s x[rs2][4:0]` | 1.1.4.2 |
| `OR` | R | `0110011` | `110` | `0000000` | `x[rd] = x[rs1] \| x[rs2]` | 1.1.4.2 |
| `AND` | R | `0110011` | `111` | `0000000` | `x[rd] = x[rs1] & x[rs2]` | 1.1.4.2 |

### 3.1. Regras por Grupo

| Grupo | Regra do manual | Seção |
| :--- | :--- | :--- |
| Aritmética | `ADD`, `SUB` e `ADDI` ignoram o estouro e gravam os 32 bits baixos | 1.1.4 |
| Comparação | `SLTIU` estende o imediato com sinal e só então o trata como sem sinal | 1.1.4.1 |
| Deslocamentos por constante | O bit 30 escolhe entre deslocamento lógico e aritmético à direita | 1.1.4.1 |
| Deslocamentos por registrador | A quantidade são os 5 bits baixos de `rs2` | 1.1.4.2 |
| `AUIPC` | Soma o imediato superior ao endereço da própria instrução | 1.1.4.1 |
| Saltos e desvios | Não há delay slot | 1.1.5 |
| `JAL` | Alcance de $\pm 1$ MiB a partir do `pc` | 1.1.5.1 |
| `JALR` | Soma `rs1` ao deslocamento de 12 bits sem escalar e zera o bit 0 do resultado | 1.1.5.1 |
| Desvios condicionais | Alcance de $\pm 4$ KiB a partir do `pc` | 1.1.5.2 |
| Loads | Enviam ao registrador o byte, a meia-palavra ou a palavra, com extensão de sinal (`LB`, `LH`) ou de zero (`LBU`, `LHU`) | 1.1.6 |
| Stores | Gravam os 8, 16 ou 32 bits baixos de `rs2` | 1.1.6 |

No Core, a ULA, o decodificador e os extensores implementam cada linha da tabela de instruções; a tabela de sinais de controle de cada instrução está em [DECODER.md](DECODER.md) e a operação da ULA em [ULA.md](ULA.md).

## 4. Memória de Dados

Seção 1.1.6 do manual.

| Requisito | Regra |
| :--- | :--- |
| Espaço de endereços | Endereçamento por byte, 32 bits |
| Ordem dos bytes | Definida pelo ambiente de execução; em little-endian o byte menos significativo fica no menor endereço |
| Acesso naturalmente alinhado | Nunca gera exceção de desalinhamento |
| Acesso desalinhado | O ambiente de execução define se ele completa, gera exceção de desalinhamento ou de acesso, e se a exceção é fatal; o acesso pode ser lento e não é garantido atômico |
| Load com destino `x0` | Continua gerando exceções e efeitos colaterais |

O Core usa a ordem little-endian. Na palavra de 32 bits, o byte de endereço $4k + i$ ocupa os bits $[8i + 7 : 8i]$, e o gerenciador de stores e o extensor de leitura usam os dois bits baixos do endereço efetivo para escolher a faixa de bytes. Um load com destino `x0` acessa a memória e passa pela mesma verificação de alinhamento, apenas não grava o resultado.

Acessos desalinhados que ficam na memória principal são executados em hardware quando o genérico `has_zicclsm` está ativo (padrão); os demais geram a exceção de load ou store desalinhado (causas 4 e 6). Os casos estão em [ACESSO_DESALINHADO.md](../../ACESSO_DESALINHADO.md).

## 5. `FENCE`, `ECALL` e `EBREAK`

### 5.1. `FENCE`

Seção 1.1.7 do manual. A instrução ordena operações de entrada e saída e de memória, vistas por outros harts e dispositivos, segundo os conjuntos predecessor e sucessor (qualquer combinação de I, O, R e W) e o campo `fm`. Os campos `rs1` e `rd` são reservados; implementações da base os ignoram. Valores reservados de `fm`, predecessor e sucessor são tratados como um `FENCE` normal, e `FENCE.TSO` pode ser implementado como `FENCE RW,RW`. O manual admite que uma implementação mínima execute `FENCE` como `NOP`.

| Aspecto | Comportamento do Core |
| :--- | :--- |
| Decodificação | Legal quando `opcode` é `0001111` e `funct3` é `000`, sem examinar `fm`, predecessor, sucessor, `rs1` nem `rd` |
| Efeito | Nenhum; o decodificador entrega os sinais de um `NOP` (sem escrita em registrador nem acesso à memória) |
| `FENCE.TSO` e valores reservados | Executam como o `FENCE` comum, porque o decodificador examina apenas `opcode` e `funct3` |
| `FENCE.I` | Pertence à extensão Zifencei e é ilegal quando o genérico `has_zifencei` está desativado ([FENCE_I.md](../../FENCE_I.md)) |

### 5.2. `ECALL` e `EBREAK`

Seção 1.1.8 do manual. Ambas são instruções SYSTEM do formato I. `ECALL` solicita um serviço ao ambiente de execução, com parâmetros definidos por ele, e `EBREAK` devolve o controle a um depurador. O manual admite que implementações simples tratem todas as instruções SYSTEM com um único trap.

| Condição | `ECALL` | `EBREAK` |
| :--- | :--- | :--- |
| Codificação exigida pelo Core | `opcode` `1110011`, `funct3` `000`, `rd` e `rs1` iguais a `x0`, campo `funct12` (bits 31 a 20) igual a `0x000` | Igual, com `funct12` igual a `0x001` |
| Com a extensão Zicsr | Exceção de causa 11 (chamada de ambiente do modo M), com `mtval` igual a 0 e redirecionamento do `pc` para `mtvec` | Exceção de causa 3 (breakpoint), com `mtval` igual a 0 e redirecionamento do `pc` para `mtvec` |
| Sem a extensão Zicsr | A saída `o_trap` do Core sinaliza a ocorrência, com a causa e o `pc` da instrução; o fluxo segue sem redirecionamento | Igual ao `ECALL`, com causa 3 |

Qualquer outra instrução SYSTEM que não seja de acesso a CSR, `MRET` ou `WFI`, incluindo `ECALL` ou `EBREAK` com `rd` ou `rs1` diferentes de `x0`, é ilegal e gera a causa 2. Os detalhes do trap estão em [ARCHITECTURE.md](../../ARCHITECTURE.md), seção 3.2.

## 6. `NOP` e Instruções HINT

Seções 1.1.4.3 e 1.1.9 do manual. O `NOP` canônico é `ADDI x0, x0, 0`. As instruções HINT, em sua maioria computacionais com `rd` igual a `x0` ou `FENCE` com conjunto vazio, só alteram o `pc` e contadores de desempenho, e uma implementação simples pode executá-las como instruções comuns sem efeito visível.

O Core executa as HINT computacionais como instruções comuns, e o descarte da escrita em `x0` as torna sem efeito. Os marcadores de semihosting (`SLLI x0, x0, 31` e `SRAI x0, x0, 7`) seguem o mesmo caminho. `PAUSE` é um `FENCE` e executa como `NOP`.

## 7. Alinhamento de Alvos de Salto

Seções 1.1.2, 1.1.5.1 e 1.1.5.2 do manual. Com `IALIGN` igual a 32, o alvo de salto ou desvio tomado que não seja múltiplo de 4 gera a exceção de endereço de instrução desalinhado, reportada na própria instrução de salto e não no alvo. Um desvio condicional não tomado nunca a gera.

| Aspecto | Comportamento do Core |
| :--- | :--- |
| `IALIGN` | 32; o Core não implementa instruções comprimidas |
| Verificação | Em EX, sobre o alvo de `JAL`, `JALR` e desvios tomados; basta o bit 1 do alvo ser 1 (o bit 0 já é zero) |
| Com a extensão Zicsr | Exceção de causa 0, com `mtval` igual ao alvo |
| Sem a extensão Zicsr | O alinhamento do alvo não é verificado |

## 8. Instruções Reservadas e Ilegais

Seção 1.1.2 do manual: o comportamento de codificações reservadas é não especificado, e algumas plataformas exigem exceção de instrução ilegal. O Core classifica como ilegal toda palavra que não seja uma das instruções da base, de `FENCE`, de SYSTEM ou de uma extensão ativa, o que inclui os casos da tabela.

| Caso ilegal | Exemplo |
| :--- | :--- |
| Bits `[1:0]` diferentes de `11` | Instruções comprimidas |
| `opcode` inexistente | `1111111` |
| `funct3` inválido para o `opcode` | `LOAD` com `funct3` `011`; `STORE` com `funct3` `011`; `BRANCH` com `funct3` `010`; `JALR` com `funct3` diferente de `000` |
| `funct7` inválido em deslocamento por constante | `SLLI` com `funct7` diferente de `0000000` |
| `funct7` inválido em instrução R | `SUB` e `SRA` são os únicos com `funct7` `0100000` |

Com a extensão Zicsr, a instrução ilegal gera a exceção de causa 2; sem ela, a saída `o_trap` sinaliza o evento. As instruções de multiplicação e divisão, de acesso a CSR e `FENCE.I` deixam de ser ilegais quando a extensão correspondente está ativa.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
