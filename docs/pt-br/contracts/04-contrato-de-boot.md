# 4. Fragmentos de Boot por Extensão

## 1. Escopo

A BOOT_MEMORY de uma plataforma é montada a partir de um fragmento de assembly por extensão, guardado ao lado do RTL da extensão. Cada fragmento deixa em estado conhecido a parte do núcleo que a sua extensão introduz, e o programa que roda depois (o `crt0` do picolibc, um sistema operacional de tempo real ou um teste) parte desse estado. A BOOT não faz `sp`, `gp`, `tp`, `.data` nem `.bss`, que são do `crt0`.

O Core não exige extensão nenhuma. Uma plataforma que liga só a base RV32I ou RV32E não inclui nenhuma instrução desses fragmentos.

## 2. Contrato de inclusão

O `boot_core.S` do Insper-RISC-V inclui os cinco arquivos sempre, depois do `boot_config.h` gerado pelo Tools, sem nenhum `#if` do lado de quem inclui. Cada fragmento se desliga pela própria macro.

| Arquivo | Macro que liga o fragmento | Sem a macro |
| :--- | :--- | :--- |
| `src/Zicsr/boot.inc` | `RV32_HAS_ZICSR` | Nenhuma instrução |
| `src/Zicntr/boot.inc` | `RV32_HAS_ZICNTR` | Nenhuma instrução |
| `src/Zihpm/boot.inc` | `RV32_HAS_ZIHPM` | Nenhuma instrução |
| `src/Sscofpmf/boot.inc` | `RV32_HAS_SSCOFPMF` | Nenhuma instrução |
| `src/Zifencei/boot.inc` | `RV32_HAS_ZIFENCEI` | Nenhuma instrução |

A ordem de inclusão é fixa e é a da tabela. O fragmento do Zicsr vem primeiro porque desliga as interrupções antes de qualquer outro CSR mudar, e o do Zifencei vem por último porque o `fence.i` é a última instrução de inicialização.

Cada fragmento obedece a cinco regras.

| Regra | Valor |
| :--- | :--- |
| Registradores | Só `t0`, `t1` e `t2` (`x5` a `x7`, que existem no RV32E), e na prática só `t0` |
| Rótulos | Nenhum rótulo global. Os fragmentos de laço usam símbolos locais do montador que não vão para a tabela de símbolos |
| Dados e pilha | Nenhum dado, nenhum acesso à memória, nenhuma pilha |
| Símbolo externo | `rv32_boot_trap`, referenciado pelo fragmento do Zicsr e definido por quem inclui, em endereço múltiplo de 4 |
| Base | Nenhuma dependência do `RV32_IS_E`, e nenhum registrador acima de `x15` |

O símbolo `rv32_boot_trap` é um tratador seguro, que nunca retorna ao código interrompido.

## 3. Estado que cada fragmento deixa

| Extensão | Estado depois do fragmento | Seção do manual |
| :--- | :--- | :--- |
| Zicsr | `mstatus` zerado (`MIE` e `MPIE` em 0), `mie` zerado, `mscratch` zerado, `mtvec` com `BASE` em `rv32_boot_trap` e `MODE` direto. Com `RV32_HAS_INTERRUPTS`, `mip` também zerado | Volume II, 2.1.1.6, 2.1.1.7, 2.1.1.9 e 2.1.1.13 |
| Zicntr | `mcycle`, `mcycleh`, `minstret` e `minstreth` em 0, e os bits 0 e 2 de `mcountinhibit` em 0 (os dois contadores correm a partir do fim do fragmento) | Volume I, capítulo 6, seção 6.1, e volume II, 2.1.1.10 e 2.1.1.12 |
| Zihpm | `mhpmevent3` a `mhpmevent31` em 0, `mhpmcounter3` a `mhpmcounter31` e as metades altas em 0, e os bits 3 a 31 de `mcountinhibit` em 0 | Volume I, capítulo 6, seção 6.2, e volume II, 2.1.1.10 e 2.1.1.12 |
| Sscofpmf | `mhpmevent3h` a `mhpmevent31h` em 0 (`OF` e `MINH` limpos) e o bit 13 de `mip` (`LCOFIP`) em 0 | Volume II, capítulo 14 e seções 3.1.9 e 3.1.10 |
| Zifencei | Nenhum CSR. Executa `fence.i` | Volume I, capítulo 4 |

A BOOT pode ser executada de novo sem reset do hardware, quando o ponto de espera dos testes recomeça pelo `_reset`. Por isso os fragmentos não supõem o valor de reset de nenhum CSR e escrevem todo valor que o estado conhecido exige.

### 3.1. Escolhas de valor

| Valor | Escolha |
| :--- | :--- |
| `mstatus = 0` | Desliga as interrupções globais (`MIE`) e zera o `MPIE`, para um `mret` perdido não reabrir as interrupções. O `MPP` é fixo em máquina no Core |
| `mtvec.MODE = 0` | O modo direto leva todo trap ao `BASE`, o que basta para um tratador que só trata falha. O modo vetorado só existe com `RV32_HAS_INTERRUPTS` |
| `mip` | Os bits de software, temporizador e externo espelham a plataforma e não são escritos pelo programa. O fragmento escreve zero em `mip` só para os bits que o hart deixa escrever |
| `mcounteren` | Não é escrito. O Core só tem o modo M, e o manual diz que nesse caso o registrador não deve existir |
| `mcountinhibit` | O Zicntr inibe `mcycle` e `minstret` só durante a escrita das metades e libera os dois no fim, e o Zihpm libera os contadores de eventos no fim. Os dois fragmentos tocam bits disjuntos, de modo que a presença de um não depende do outro |
| `mhpmevent = 0` | O evento 0 é "nenhum evento": o contador não conta até a aplicação escolher um evento |
| Zero antes de liberar | Os seletores de evento são zerados antes dos contadores, e a inibição só é liberada depois dos dois, para nenhum contador contar durante a limpeza |
| `mip.LCOFIP` | Um contador pode ter estourado entre o fragmento do Zicsr e o do Zihpm de uma execução anterior, de modo que o fragmento do Sscofpmf limpa o bit de pendência depois de limpar `OF` |

### 3.2. Contadores parcialmente implementados

O Core implementa só os `hpm_counters` primeiros contadores de eventos, mas responde aos 29 endereços. Um índice sem contador lê zero e ignora a escrita, sem exceção. O fragmento do Zihpm escreve os 29 índices sem consultar `hpm_counters` nem `hpm_width`, e o resultado vale para qualquer valor desses generics.

## 4. Extensões sem fragmento

As extensões abaixo não têm estado a inicializar, e por isso o Core não tem fragmento para elas.

| Extensão | Motivo |
| :--- | :--- |
| M e Zmmul | A unidade multiplicadora e divisora não guarda estado entre instruções |
| Zicclsm | Só define o comportamento de acesso desalinhado, sem registrador |
| Zicond e Zimop | Instruções sem estado arquitetural próprio |
| Zihintntl e Zihintpause | Dicas que o núcleo executa como `NOP` |
| Interrupções e falhas de acesso | O estado está nos CSRs do Zicsr. Com `RV32_HAS_INTERRUPTS` o fragmento do Zicsr zera `mip`, e com `RV32_HAS_ACCESS_FAULTS` o `mtvec` já cobre o que há a inicializar |

## 5. Tamanho

O tamanho de cada fragmento com a sua macro ligada, em instruções de 4 bytes, não depende da base.

| Fragmento | Instruções | Bytes |
| :--- | ---: | ---: |
| Zicsr, sem `RV32_HAS_INTERRUPTS` | 6 | 24 |
| Zicsr, com `RV32_HAS_INTERRUPTS` | 7 | 28 |
| Zicntr | 6 | 24 |
| Zihpm | 89 | 356 |
| Sscofpmf | 31 | 124 |
| Zifencei | 1 | 4 |

Com todos os fragmentos ligados são 536 bytes, que cabem na BOOT_MEMORY de 4 KiB junto com a seleção de banco e a validação por CRC.

## 6. Verificação

Os scripts estão em `tests/boot` e rodam com o toolchain da imagem `ci-elf` (prefixo `riscv32-unknown-elf-`) e o Spike.

```bash
make test-boot
```

| Script | O que confere |
| :--- | :--- |
| `assemble.sh` | Cada fragmento desligado gera zero bytes, mesmo com todas as outras macros ligadas. Ligado, gera a quantidade de instruções da seção 5. Em cada combinação válida das macros das cinco extensões, a saída é a concatenação ordenada dos fragmentos, o `fence.i` é a última instrução quando existe, só `x0` e `x5` a `x7` aparecem, não há dado nem símbolo além de `rv32_boot_trap`. As macros das extensões sem estado e o RV32E não mudam a saída |
| `spike.sh` | Suja o estado que cada extensão limpa, executa os fragmentos no Spike com a `--isa` casada e confere o estado depois deles, além de que nenhum outro registrador mudou. Roda também cada fragmento sozinho |

O programa do Spike termina no `tohost` do HTIF, e o código de falha identifica a verificação que falhou.

| Código | Verificação |
| ---: | :--- |
| 1 | `MIE`, `MPIE` ou `MPRV` de `mstatus` diferente de 0 |
| 2 | `mie` diferente de 0 |
| 3 | `mscratch` diferente de 0 |
| 4 | `mtvec` diferente do endereço de `rv32_boot_trap` |
| 5 | `LCOFIP` de `mip` diferente de 0 |
| 6 | Bit de `mcountinhibit` que o fragmento limpa diferente de 0 |
| 7 | `mcycleh` diferente de 0 |
| 8 | `minstreth` diferente de 0 |
| 9 | `mcycle` acima de 4095 |
| 10 | `minstret` acima de 4095 |
| 11 | Algum `mhpmevent`, `mhpmcounter` ou metade alta diferente de 0 |
| 12 | Algum `mhpmeventh` diferente de 0 |
| 20 | Um registrador fora de `t0` a `t2` mudou |
| 30 | Trap com o estado sujo |
| 31 | Trap em `rv32_boot_trap` |

O Spike não guarda valor nos contadores `mhpmcounter` nem nos seletores sem evento modelado, que leem zero, de modo que para esses a verificação confere que o fragmento acessa os 29 índices sem trap. A escrita de zero em cada contador no RTL é coberta pelos testes do banco de eventos do Zihpm.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
