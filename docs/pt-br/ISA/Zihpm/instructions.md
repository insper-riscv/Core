# Zihpm, o que o manual exige

Capítulo 6 do manual não privilegiado ([Zicntr and Zihpm Extensions for Counters](https://docs.riscv.org/reference/isa/v20260120/unpriv/counters.html)) e capítulo 1 do manual privilegiado ([Control and Status Registers](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html)).

Este documento resume o que os manuais de ISA (versão 20260120) exigem da extensão Zihpm. As fontes são o Capítulo 6 do volume não privilegiado, "Zicntr and Zihpm Extensions for Counters, Version 2.0", seção 6.1.2, e o Capítulo 1 do volume privilegiado, com as seções dos CSRs de máquina citadas abaixo. O texto é uma paráfrase. O capítulo 6 define também o Zicntr, descrito em [Zicntr](../Zicntr/instructions.md). Como o Core implementa cada ponto está em [description.md](description.md), e o acesso aos CSRs em si (`CSRRW`, `CSRRS`, `CSRRC` e variantes) está em [Zicsr](../Zicsr/instructions.md).

## 1. Visão geral (Capítulo 6, Seção 6.1.2)

A extensão dá acesso, do nível não privilegiado, a até 29 contadores de desempenho de 64 bits. Cada contador é lido por um CSR somente leitura de `XLEN` bits, nos endereços $0xC03$ a $0xC1F$. No RV32 (`XLEN = 32`) as metades altas ficam nos endereços $0xC83$ a $0xC9F$. A extensão depende do Zicsr.

## 2. Zihpm, contadores de desempenho (Seção 6.1.2)

O Zihpm acrescenta até 29 contadores de 64 bits, `hpmcounter3` a `hpmcounter31`, nos endereços $0xC03$ a $0xC1F$. No RV32 as metades altas são `hpmcounter3h` a `hpmcounter31h`, nos endereços $0xC83$ a $0xC9F$.

| Aspecto | O que o manual diz |
| :--- | :--- |
| Quantidade | Depende da plataforma, de zero a 29 |
| Largura | 64 bits |
| Eventos contados | Definidos pela plataforma |
| Contador não implementado | O acesso pode gerar exceção de instrução ilegal ou devolver uma constante |
| Controle de acesso | Descrito no manual de arquitetura privilegiada |
| Leitura de 64 bits no RV32 | A sequência metade alta, metade baixa, metade alta recupera um valor válido quando as duas leituras da metade alta coincidem |

## 3. Contadores de máquina (Capítulo 1, volume privilegiado)

Os CSRs de máquina que controlam os contadores de desempenho estão na [seção 2.1.1.10](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-10-hardware-performance-monitor) do manual privilegiado, e a inibição da contagem na [seção 2.1.1.12](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-12-machine-counter-inhibit-mcountinhibit-register).

| Registrador | Endereço | O que o manual diz |
| :--- | :--- | :--- |
| `mhpmcounter3` a `mhpmcounter31` | $0xB03$ a $0xB1F$ | Contadores de 64 bits, registradores WARL; os espelhos de leitura são os `hpmcounterN` |
| `mhpmcounter3h` a `mhpmcounter31h` | $0xB83$ a $0xB9F$ | Metades altas dos contadores no RV32 |
| `mhpmevent3` a `mhpmevent31` | $0x323$ a $0x33F$ | Seletores de evento WARL; o significado dos eventos é da plataforma e o evento 0 significa nenhum evento |
| `mcountinhibit` | $0x320$ | Registrador WARL de 32 bits; o bit 0 inibe `mcycle`, o bit 1 vale sempre zero porque o `time` não é inibível, o bit 2 inibe `minstret` e os bits de 3 a 31 inibem cada contador de eventos |

O manual diz que todos os contadores devem existir, mas que é uma implementação legal fixar em zero um contador e o seu seletor de evento. Um contador com o bit de inibição em um mantém o valor, e um contador com o bit em zero conta normalmente. Uma escrita explícita em um contador no mesmo ciclo de um evento prevalece sobre o incremento.

## 4. Endereços

Os endereços de `hpmcounterN` estão na [tabela de endereços não privilegiados](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-1-currently-allocated-risc-v-unprivileged-csr-addresses), e os de `mhpmcounterN`, `mhpmeventN` e `mcountinhibit` na [tabela de endereços de máquina](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-4-currently-allocated-risc-v-machine-level-csr-addresses). A descrição do que o Core oferece nesses endereços está em [description.md](description.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
