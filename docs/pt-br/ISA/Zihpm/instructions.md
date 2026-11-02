# Zihpm, o que o manual exige

Capítulo 6 do manual ([Zicntr and Zihpm Extensions for Counters](https://docs.riscv.org/reference/isa/v20260120/unpriv/counters.html)).

Este documento resume o que o manual de ISA não privilegiada (versão 20260120) exige da extensão Zihpm. A fonte é o Capítulo 6, "Zicntr and Zihpm Extensions for Counters, Version 2.0", seção 6.1.2, e o texto abaixo é uma paráfrase. O capítulo define também o Zicntr, descrito em [Zicntr](../Zicntr/instructions.md). Como o Core implementa cada ponto está em [description.md](description.md), e o acesso aos CSRs em si (`CSRRW`, `CSRRS`, `CSRRC` e variantes) está em [Zicsr](../Zicsr/instructions.md).

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

## 3. Fora do escopo deste capítulo

O capítulo não define os CSRs de máquina que controlam os contadores de desempenho. `mhpmcounterN` e `mhpmeventN` estão na [seção 2.1.1.10](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-10-hardware-performance-monitor) do manual de arquitetura privilegiada, e a inibição da contagem (`mcountinhibit`) na [seção 2.1.1.12](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-12-machine-counter-inhibit-mcountinhibit-register). Os endereços de `hpmcounterN` estão na [tabela de endereços não privilegiados](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-1-currently-allocated-risc-v-unprivileged-csr-addresses), e os de `mhpmcounterN`, `mhpmeventN` e `mcountinhibit` na [tabela de endereços de máquina](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-4-currently-allocated-risc-v-machine-level-csr-addresses). A descrição do que o Core oferece nesses endereços está em [description.md](description.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
