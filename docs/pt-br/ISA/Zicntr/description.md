# Zicntr no Core

Este documento descreve como o Core implementa os contadores básicos `cycle`, `time` e `instret`, e o bloco contador de 64 bits que o Zihpm também usa. O que o manual exige está em [instructions.md](instructions.md), os contadores de desempenho estão em [Zihpm](../Zihpm/description.md), e o banco de CSRs que os hospeda (leitura, escrita atômica, ilegalidade) está em [Zicsr](../Zicsr/description.md).

## 1. Generics

| Generic | Entidade | Padrão | Efeito |
| :--- | :--- | :--- | :--- |
| `has_zicntr` | `core` | `false` | Instancia `mcycle`, `minstret` e `time` com seus espelhos, e o registrador `mcountinhibit`; exige `has_zicsr` |
| `tick_cycles` | `core` | 50 | Ciclos de clock por tick do `time` (50 dá 1 MHz a 50 MHz) |

A elaboração falha se `has_zicntr` for ligado sem `has_zicsr`. O Zicntr independe do Zihpm.

## 2. Bloco contador de 64 bits

Todo contador é uma instância de `counter64`, que guarda o valor em duas metades. Com a largura padrão de 64 bits, cada metade tem 32 bits. O Zihpm instancia o mesmo bloco com uma largura $W$ de 1 a 64 bits, em que a metade baixa guarda os $\min(W,32)$ bits baixos e a metade alta os $W-32$ restantes (ausente quando $W \le 32$).

| Aspecto | Comportamento |
| :--- | :--- |
| Incremento | A metade baixa soma 1 nos ciclos com incremento habilitado |
| Vai-um | Quando a metade baixa estava em $2^{32}-1$, o vai-um fica registrado e a metade alta soma 1 no ciclo seguinte, sem somador de 64 bits no caminho combinacional |
| Leitura | A metade alta lida já inclui o vai-um pendente, então o par lido é sempre o valor ideal de 64 bits |
| Escrita na metade baixa | Substitui o valor e cancela o incremento e o vai-um do mesmo ciclo |
| Escrita na metade alta | Substitui o valor e descarta o vai-um pendente |
| Largura | Os bits de cada saída acima da largura da metade leem zero, e uma escrita guarda só os bits que cabem; o vai-um sai da metade baixa quando todos os seus bits valem um |
| Reset | Zera as duas metades e o vai-um |

Uma escrita vence o incremento do próprio ciclo, em cada metade.

## 3. Contadores do Zicntr

### 3.1. Endereços e regras

Há 3 contadores de 64 bits. O Core não implementa `mcounteren`, e o acesso a esse endereço é ilegal. O Core só tem o modo M, e o manual privilegiado diz que, em harts sem modo U, o `mcounteren` não deve existir ([seção 2.1.1.11](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#mcounteren)).

| Contador | Metade baixa | Metade alta | Espelho somente leitura (baixa e alta) | Incrementa | Escrita |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `mcycle` | `0xB00` | `0xB80` | `cycle` em `0xC00` e `0xC80` | A cada ciclo de clock, inclusive nos ciclos de parada, salvo inibição | Sim, em cada metade |
| `minstret` | `0xB02` | `0xB82` | `instret` em `0xC02` e `0xC82` | A cada instrução retirada, um ciclo depois da retirada, salvo inibição ou cancelamento | Sim, em cada metade |
| `time` | `0xC01` | `0xC81` | Só existe a forma de leitura | A cada tick do divisor, sem inibição | Não |

Os endereços `0xB01` e `0xB81` não existem, e o `time` não tem forma de máquina. Escrever efetivamente em `cycle`, `instret` ou `time` é acesso ilegal (`mcause = 2`). Sem `has_zicntr` os endereços de contador são inexistentes e o acesso é ilegal.

### 3.2. Retirada de instruções

A instrução em EX é retirada quando é válida, o pipeline anda e não há exceção. O pulso de retirada fica pendente por um ciclo, de modo que uma exceção de load ou store tomada em MEM o cancele, e o acesso que falha não conta em `minstret`.

| Situação | Efeito em `minstret` |
| :--- | :--- |
| Retirada pendente | A leitura de `minstret` e `instret` já soma a retirada pendente, e a soma efetiva ocorre no ciclo seguinte |
| Exceção de MEM no ciclo seguinte | A retirada é cancelada e não conta |
| Escrita em `minstret` no mesmo ciclo | A retirada da própria instrução de escrita é descartada |
| Instrução que causa exceção em EX | Não gera pulso de retirada |

### 3.3. Divisor de tick e `time`

O `time` soma 1 a cada pulso do divisor de tick. O divisor conta de 0 a $tick\_cycles - 1$, emite o pulso no ciclo em que a contagem chega ao fim e volta a 0 no ciclo seguinte. O reset zera a contagem.

$$f_{time} = \frac{f_{clock}}{tick\_cycles}$$

O Core não tem entrada externa de tempo. O `time` deriva do clock do próprio Core, e a resolução é fixada por `tick_cycles` (no mínimo 1).

## 4. `mcountinhibit`

O registrador `mcountinhibit` fica em `0x320`. Seus bits que aceitam escrita dependem do que o perfil inclui, e os demais leem zero e ignoram escrita. O registrador existe quando há `has_zicntr` ou `has_zihpm`, e os bits de contadores de eventos estão em [Zihpm](../Zihpm/description.md).

| Bit | Inibe | Existe quando |
| :--- | :--- | :--- |
| 0 | `mcycle` | `has_zicntr` |
| 1 | Nada (o `time` não é inibível) | Nunca |
| 2 | `minstret` | `has_zicntr` |

Um contador inibido mantém o valor e continua legível e gravável. A inibição de `minstret` também suspende a soma da retirada pendente que a leitura mostra.

## 5. Endereço inexistente

Sem `has_zicntr` os endereços de `mcycle`, `minstret`, `time`, seus espelhos e `mcountinhibit` (quando não há contador de eventos) são inexistentes. Ler ou escrever neles sinaliza acesso CSR ilegal, que o Core trata como exceção de instrução ilegal (`mcause = 2`). Não há valor constante de retorno. O mesmo vale para a escrita efetiva em `cycle`, `instret` e `time`.

## 6. Verificação formal

| Prova | Arquivo | O que garante |
| :--- | :--- | :--- |
| `counter64` | `formal/counter64_props.sv` | O par de metades é sempre o valor ideal de 64 bits, a escrita vence o incremento, o vai-um nunca se perde e o valor não decresce sem escrita (indução, cover) |
| `csr_file` com Zicntr | `formal/csr_cntr_props.sv` | Valores lidos de `mcycle`, `minstret` e espelhos, escrita por metade, espelhos e `time` somente leitura, bits 0 e 2 de `mcountinhibit` e cancelamento de retirada (BMC de 6 ciclos, cover) |

O procedimento das provas está em [FORMAL.md](../../formal/FORMAL.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
