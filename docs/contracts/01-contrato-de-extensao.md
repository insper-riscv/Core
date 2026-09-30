# 1. Contrato de extensão

## O que é, e o que não é

O **ISA** (a especificação RISC-V) diz *o que* uma instrução faz: opcodes,
`funct`, semântica. O **contrato de extensão** diz *como o hardware de uma
extensão se pluga no pipeline deste core*: quantos ciclos ela ocupa, como
para o pipeline, como devolve o resultado, como entra no forwarding. A ISA não
especifica nada disso (é microarquitetura), e é exatamente isso que hoje
está espalhado pelo core sem fronteira.

Uma extensão = uma pasta do Core (`I/`, `M/`, no futuro `Zicsr/`, `Zifencei/`)
que entrega tudo abaixo e nada mais. O pipeline (`common/`) só conhece o
contrato, não a extensão.

## Como o M está integrado hoje (verificado)

O M funciona, mas está costurado em quatro pontos do código comum:

| Ponto | Onde | O que acontece |
| :--- | :--- | :--- |
| Decodificação | `control_unit.vhd`, ramo R-type: `if funct7 = "0000001" then isMulDiv <= '1'` | o decodificador central conhece o M |
| Sub-operação | `decoderM.vhd`: `funct3` (3 bits) → palavra de controle de 5 bits (Mul, MulH, MulHSU, MulHU, Div, DivU, Rem, RemU) | dentro de `multdiv` |
| Execução | `multdiv.vhd`: `clk, rst, start, busy, done, opCode(3), valorA, valorB, saida`; a divisão leva ~37 ciclos | |
| Pipeline | `rv32im_pipeline_core.vhd`: `muldiv_stall = busy or done` congela IF/ID/EX/MEM (`en => muldiv_stall_n`); `hazard_detection_unit`: `stall <= load_use or muldiv_busy`; mux de resultado `ex_alu_mux_result <= ex_muldiv_result when ex_isMulDiv` | |
| Start | `mul_start_pulse <= ex_isMulDiv and ex_valid and not mul_started_q` | um pulso por instrução, gerado em EX (correção do PR #33) |

Sobras a limpar: `multdiv` tem portas de demonstração (`SW`, `LEDR`) e
generics que não usa; o sinal antigo `startMul_raw`/`isMulDiv_d` ainda existe,
sem alimentar a unidade.

## O que o contrato precisa definir

### 1.1 Decodificação
A extensão declara quais `(opcode, funct3, funct7)` reivindica e devolve um
pacote de controle. **Proposta:** cada extensão tem seu pacote
`<ext>_decode` (função pura de `instruction`) e o decodificador comum só
combina os pacotes; conflito de reivindicação (dois pacotes aceitando a mesma
instrução) é erro de simulação. Campos mínimos do pacote:

| Campo | Significado |
| :--- | :--- |
| `claims` | a extensão reconhece esta instrução |
| `uses_rs1`, `uses_rs2` | para o forwarding e a detecção de hazard |
| `writes_rd` | escreve registrador |
| `unit_op` | código da operação, repassado à unidade de execução |
| `multicycle` | a unidade pode ficar ocupada mais de um ciclo |

### 1.2 Unidade de execução
Interface fixa, que o `multdiv` já quase cumpre:

| Sinal | Dir. | Regra |
| :--- | :--- | :--- |
| `clk`, `rst` | in | |
| `start` | in | **um pulso de um ciclo por instrução**, gerado pelo pipeline (em EX), nunca por detecção de borda em ID |
| `op` | in | `unit_op` do pacote de decodificação, estável enquanto `busy` |
| `a`, `b` | in | operandos já resolvidos pelo forwarding |
| `busy` | out | **eager**: `'1'` já no ciclo em que `start` é visto (combinacional com `start`) e até o ciclo anterior ao `done` |
| `done` | out | pulso de um ciclo em que `result` é válido; nesse ciclo `busy` já voltou a `'0'` |
| `result` | out | estável enquanto `done` e no ciclo seguinte |

O pipeline fica parado enquanto `busy or done` (é o `muldiv_stall`): o `done`
entra na conta porque, no ciclo dele, `busy` já caiu mas o resultado ainda está
sendo capturado. Latência fixa ou variável é livre, mas `busy`/`done` precisam
dizer a verdade. Combinacional puro (latência 0, como a ALU) é o caso `multicycle = 0`:
`busy`/`done` ficam em `'0'` e o pipeline não para.

### 1.2.1 Modo de operação da unidade
**Decidido: por enquanto só `blocking`.** O pipeline inteiro para enquanto
`busy or done` (como o `muldiv_stall` faz hoje), mesmo para instruções que não
dependem do resultado. Um multiplicador de DSP não é solução: o objetivo é um
SoC, então a unidade M não pode depender de blocos de um fabricante. O
problema de desempenho fica registrado como issue no repositório Core; o
contrato reserva os modos `pipelined` (latência fixa, sem stall) e
`non_blocking` (`rd_pending`, para só por dependência) sem mudar a interface.

### 1.3 Efeito no pipeline
Só três efeitos são permitidos, todos por sinais do contrato, nunca
editando o pipeline por dentro:

1. **Parar** o pipeline (`busy`): o pipeline comum congela IF/ID/EX/MEM,
   como o `muldiv_stall` faz hoje; a extensão não gera `stall` próprio.
2. **Flush** (`flush_req` + `redirect_pc`): usado por Zifencei e por trap.
3. **Exceção** (`exc_valid` + `exc_cause`): reservado para Zicsr; o M e o I
   não geram exceção (nem divisão por zero: o RISC-V devolve valor definido).

### 1.4 Resultado e forwarding
O `result` entra no pipeline como resultado de EX (mux único
`ex_result`), então o forwarding existente (EX/MEM → EX, MEM/WB → EX) o trata
como um resultado de ALU, sem caso especial. Uma extensão não lê nem escreve
o banco de registradores diretamente.

### 1.5 Perfis
Um perfil (`rv32i`, `rv32im`) é a lista de extensões mais o topo que as
instancia (`Core/cores/`). `rv32i` é o pipeline sem a unidade M: uma
instrução de uma extensão que o perfil não tem **é um NOP** (decidido): o
decodificador comum não reivindica o opcode e o pipeline a deixa passar sem
efeito (sem escrita de registrador, sem parada).

**Como está implementado** (`profiles/rv32i.yaml`, `profiles/rv32im.yaml`): um
único topo, `cores/rv32im_pipeline_core.vhd`, com o generic `HAS_M`. Com
`HAS_M => false`, o `control_unit` trata `funct7 = "0000001"` como NOP
(todos os sinais de controle em zero) e a unidade `multdiv` não é instanciada
(`generate`, ligada por componente para que os arquivos de `M/` não precisem
existir na análise). O perfil `rv32i` lista só `common/`, `I/` e o topo.
`make profiles` constrói cada perfil sozinho; `ControlUnit_noM` em
`tests/python/tests.json` prova o NOP.

## Critério de aceite de uma extensão
- Testes por entidade da extensão passam sozinhos, sem o pipeline.
- `mul;mul`/`div;rem` consecutivos com operandos distintos passam (regressão
  do bug do PR #33; existe `asm/div-rem-back-to-back`).
- Nenhum arquivo de `common/` cita o nome da extensão.

## Mudanças por repositório
- **Core**: `M/` ganha `decode` e a interface acima; `control_unit` deixa de
  citar `funct7 = "0000001"`; HDU para só por `busy` genérico; remover sobras.
- **Testes**: testes por extensão usam `RV32_EXT` (já existe).
- **Certification**: `act.extensions` acompanha o perfil.

## Decisões (nenhuma em aberto)
1. ~~`mul` no perfil `rv32i`~~ **Decidido: NOP** (seção 1.5). Falta um teste que o prove (um `mul` em `rv32i` não altera registradores).
2. ~~`busy` no mesmo ciclo de `start` ou depois?~~ **Verificado: já é no mesmo ciclo (eager)** nos dois operadores (Booth e divisor). A lacuna que o `busy or done` cobre é a do fim (ciclo do `done`), não a do início. Mantido como está e escrito no contrato (1.2).
