# Extensão M: Implementação no Core

Este documento descreve como o Core executa as instruções da `M`. O que o manual exige (codificação e semântica) está em [instructions.md](instructions.md). A multiplicação é compartilhada com a `Zmmul`, e o multiplicador de Booth está descrito em [Zmmul](../Zmmul/description.md).

## 1. Configuração

O genérico `has_m` do `core` escolhe o que é instanciado.

| Genérico | Padrão | Efeito |
| :--- | :--- | :--- |
| `has_m` | `false` | Instancia o decodificador, o multiplicador e o divisor (8 instruções) |

O decodificador e a unidade de execução são gerados quando `has_m` ou `has_zmmul` vale `true`, e o divisor só quando `has_m` vale `true`. Assim, `has_m` já inclui a multiplicação, e o perfil sem divisão usa só o genérico `has_zmmul`, descrito em [Zmmul](../Zmmul/description.md). Os perfis válidos nunca combinam as duas extensões (ver o [README](../../../../README.md)).

## 2. Estrutura

| Etapa | Entidade | Função |
| :--- | :--- | :--- |
| ID | `m_decode` | Reconhece a instrução da extensão e ativa os controles |
| EX | `multdiv` | Coordena a operação, escolhe o resultado e gera a parada do pipeline |
| EX | `booth_multiplier_rv32` | Produto de 64 bits (instruções de multiplicação) |
| EX | `non_restoring_divider_rv32` | Quociente e resto de 32 bits (instruções de divisão) |
| EX | `muldiv_fusion` | Guarda a última operação para a fusão de pares |

## 3. Decodificação no Estágio ID

O decodificador reivindica a instrução quando o `opcode` é o de operações entre registradores, o `funct7` vale `0000001` e o `funct3` pertence às operações implementadas. Ao reivindicá-la, ativa três controles.

| Controle | Valor | Efeito |
| :--- | :--- | :--- |
| Seleção do resultado da unidade de multiplicação e divisão | `1` | O estágio EX usa o resultado da unidade em vez da ULA |
| Escrita em `rd` | `1` | O resultado é gravado no banco de registradores |
| Operando A | `rs1` | O primeiro operando vem de `rs1` |

O parâmetro de divisão do decodificador recebe o valor de `has_m`. Sem divisão (perfil `Zmmul`), só os `funct3` com o bit 2 em zero são reivindicados, ou seja, as quatro multiplicações.

### 3.1. Instruções Desligadas

Quando uma instrução com `funct7 = 0000001` não é reivindicada, seja porque nenhuma das extensões está ligada, seja porque o `funct3` é de divisão no perfil `Zmmul`, a unidade de controle a marca como ilegal. O estágio ID só anula essa marca para as instruções que o decodificador reivindicou. Sem as duas extensões, o estágio EX não instancia a unidade, e a parada e o resultado dela ficam fixos em zero.

## 4. Execução no Estágio EX

A `multdiv` gera um pulso de início no primeiro ciclo em que uma instrução da extensão válida entra no estágio EX, guarda o `funct3` desde esse pulso e aciona o multiplicador (bit 2 do `funct3` em zero) ou o divisor (bit 2 em um). Os operandos são os valores de `rs1` e `rs2` já com o adiantamento de dados aplicado.

O código de sinal derivado do `funct3` guardado diz quais operandos têm sinal.

| Instruções | Operando A | Operando B |
| :--- | :--- | :--- |
| `MUL`, `MULH`, `DIV`, `REM` | Com sinal | Com sinal |
| `MULHSU` | Com sinal | Sem sinal |
| `MULHU`, `DIVU`, `REMU` | Sem sinal | Sem sinal |

A multiplicação usa o multiplicador de Booth radix-2 descrito em [Zmmul](../Zmmul/description.md), que produz o produto de 64 bits e entrega as metades baixa e alta.

### 4.1. Divisor Não-Restaurador

O divisor opera sobre o módulo dos operandos nas divisões com sinal e sobre os próprios valores nas sem sinal. O resto parcial e o divisor têm 34 bits, o que comporta divisores sem sinal acima de $2^{31}$ (ver [DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md](../../bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md)). Os estados do caso normal são os da tabela.

| Estado | Ciclos | Operação |
| :--- | :--- | :--- |
| Início | 1 | Calcula o módulo dos operandos e carrega os registradores |
| Cálculo | 32 | Desloca o resto parcial; subtrai o divisor se o resto é não negativo, soma se é negativo; registra um bit do quociente |
| Correção | 1 | Soma o divisor ao resto se ele terminou negativo |
| Ajuste de sinal | 1 | Aplica os sinais: o quociente é negado se os sinais dos operandos diferem, e o resto é negado se o dividendo é negativo |

Na divisão sem sinal o ajuste copia quociente e resto sem alteração. A latência é de 35 ciclos no caso normal, a soma dos ciclos da tabela.

Os casos especiais do manual são detectados antes do cálculo e dispensam as 32 iterações; a latência é de 2 ciclos.

| Condição | Quociente | Resto |
| :--- | :--- | :--- |
| Divisor igual a zero (com ou sem sinal) | `0xFFFFFFFF` | Dividendo |
| Dividendo $-2^{31}$ e divisor $-1$ (com sinal) | `0x80000000` | `0` |

### 4.2. Resultado

Cada operador sinaliza ocupado e concluído. O resultado final é escolhido pelo `funct3` guardado.

| Instrução | Fonte |
| :--- | :--- |
| `MUL` | Metade baixa do produto |
| `MULH`, `MULHSU`, `MULHU` | Metade alta do produto, com a correção descrita em [Zmmul](../Zmmul/description.md) |
| `DIV`, `DIVU` | Quociente |
| `REM`, `REMU` | Resto |

O resultado é capturado num registrador no ciclo de conclusão e entregue ao estágio EX.

## 5. Parada do Pipeline

A `multdiv` mantém sua saída de parada ativa desde o ciclo do pulso de início, durante todo o cálculo e no ciclo de conclusão. O ciclo do pulso é coberto por um termo combinacional, de modo que a instrução para já no primeiro ciclo, e o restante vem de um flip-flop que guarda o ocupado do ciclo anterior. Assim, o pulso de conclusão não atravessa a lógica de parada do pipeline.

O `core` combina essa parada com as demais condições (ver a seção 2.4 de [ARCHITECTURE.md](../../pipeline/ARCHITECTURE.md)) e a conta no evento 1 do Zihpm. O custo por instrução, em ciclos de parada, é o da tabela.

| Caso | Latência da unidade | Ciclos de parada |
| :--- | :---: | :---: |
| Multiplicação | 33 | 35 |
| Divisão normal | 35 | 37 |
| Divisão por zero ou estouro | 2 | 4 |
| Operação fundida (seção 6) | Não se aplica | 3 |

Em todos os casos a parada dura a latência do operador mais 2 ciclos. O ocupado do operador sobe de forma combinacional no ciclo do pulso de início e só cai depois do estado de término, e a parada usa o ocupado registrado, de modo que ela cobre também o ciclo em que o resultado é capturado. A multiplicação tem latência de 33 ciclos (1 de carga e 32 passos) e para por 35. A divisão normal tem latência de 35 ciclos (1 de início, 32 iterações, 1 de correção e 1 de ajuste de sinal) e para por 37. Nos casos especiais a latência é de 2 ciclos (início e detecção) e a parada dura 4.

O efeito da parada registrada no caminho crítico está em [STALL_REGISTRADO_DO_MULTDIV.md](../../timing/STALL_REGISTRADO_DO_MULTDIV.md).

## 6. Fusão de Pares

O manual recomenda executar `MULH[[S]U]` seguido de `MUL`, e `DIV[U]` seguido de `REM[U]`, como uma só operação. A entidade `muldiv_fusion` cumpre a recomendação guardando a última operação concluída por inteiro: os dois operandos, o `funct3` e o resultado completo (o produto de 64 bits sem a correção de sinal, ou o par quociente e resto).

### 6.1. Critério de Acerto

No ciclo seguinte ao pulso de início, com os operandos já travados no estágio EX, as três condições abaixo precisam valer ao mesmo tempo, além de existir um registro válido.

| Condição | Detalhe |
| :--- | :--- |
| Mesmos valores | Os dois operandos têm os mesmos valores dos registrados, independentemente dos registradores de origem e de destino |
| Mesma família | Multiplicação, `DIV` com `REM`, ou `DIVU` com `REMU` |
| Outra operação | O `funct3` difere do registrado |

Como a comparação é por valor, o acerto é sempre correto. Não fundem a repetição da mesma operação, valores diferentes, famílias diferentes, a divisão com sinal seguida da sem sinal e uma operação diferente intercalada, porque o registro guarda só a última.

### 6.2. Sequência

No acerto, a unidade em curso é interrompida e o resultado sai do registro um ciclo depois.

| Ciclo | Evento |
| :--- | :--- |
| 0 | Pulso de início |
| 1 | Comparação e acerto |
| 2 | Término, com o resultado vindo do registro e a correção da metade alta aplicada ao modo da segunda instrução |

O registro é válido a partir da primeira operação concluída e só o reset o invalida. Uma operação fundida não o altera. Cada operação fundida é contada no evento 9 do Zihpm.

## 7. Verificação Formal

As propriedades de `formal/muldiv_fusion_props.sv` verificam a `muldiv_fusion` por BMC e cobertura (ver [FORMAL.md](../../formal/FORMAL.md)). Um modelo guarda a última operação concluída e as asserções exigem que o acerto ocorra apenas no ciclo seguinte a um início, com registro válido, mesmos valores de operandos, mesma família e outra operação. Exigem também que, no ciclo de término fundido, o registro mostre exatamente o resultado completo que a execução anterior sobre aqueles operandos entregou. As coberturas alcançam o acerto de multiplicação e de divisão e os casos de operandos iguais com família diferente ou com a mesma operação.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
