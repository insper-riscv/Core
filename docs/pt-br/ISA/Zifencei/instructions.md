# Zifencei: Instruções Exigidas pelo Manual do RISC-V

Este documento resume o que o manual de ISA não privilegiada (versão 20260120) exige da extensão Zifencei, descrita no Capítulo 4, "Zifencei Extension for Instruction-Fetch Fence, Version 2.0". A extensão define uma única instrução, `FENCE.I`. A implementação no Core está em [description.md](description.md).

## 1. Escopo da Extensão

O Capítulo 4 tem uma única seção, a 4.1, que define a instrução e as regras de uso. A extensão existe porque a sincronização entre stores e busca de instruções não faz parte da base `I`.

## 2. Instrução FENCE.I

### 2.1. Codificação

A instrução ocupa o opcode `MISC-MEM`, o mesmo da `FENCE`, e se distingue dela pelo campo `funct3`.

| Campo | Bits | Valor |
| :--- | :--- | :--- |
| `opcode` | $[6:0]$ | `0001111` (`MISC-MEM`) |
| `funct3` | $[14:12]$ | `001` |
| `funct12` | $[31:20]$ | Reservado, zero |
| `rs1` | $[19:15]$ | Reservado, zero |
| `rd` | $[11:7]$ | Reservado, zero |

O manual apresenta `funct12`, `rs1` e `rd` como campos não usados, reservados para barreiras de granularidade mais fina em extensões futuras. Pela regra de compatibilidade futura, as implementações base devem ignorá-los e o software padrão deve zerá-los. O manual não define um campo de imediato próprio para a instrução; o campo `funct12` ocupa as posições que uma instrução do tipo I usaria para o imediato.

### 2.2. Semântica

| Propriedade | O que o manual exige |
| :--- | :--- |
| Visibilidade na própria hart | Um store em memória de instruções não tem garantia de ser visto pela busca de instruções da mesma hart até que ela execute `FENCE.I` |
| Efeito da instrução | Depois da `FENCE.I`, uma busca de instrução posterior na hart enxerga os stores anteriores que já eram visíveis a essa hart |
| Ordenação | Os acessos explícitos à memória anteriores da hart ficam ordenados antes das buscas de instrução posteriores |
| Busca e acessos da própria instrução | Uma busca de instrução fica ordenada antes dos acessos explícitos à memória que a própria instrução causa |

### 2.3. Relação com a FENCE

A `FENCE` comum ordena acessos à memória de dados, e a `FENCE.I` ordena esses acessos contra as buscas de instrução da própria hart. São instruções distintas, com `funct3` diferente, e uma não substitui a outra.

## 3. Requisitos para o Software

1. O programa que grava código na memória deve executar `FENCE.I` depois do store e antes de executar o código novo.
2. O software só deve contar com a `FENCE.I` se a thread não migrar para outra hart, pois a instrução afeta apenas a hart local.
3. Os campos reservados devem ser zerados.

## 4. Multiprocessadores e Harts Remotas

A `FENCE.I` não garante que as buscas de instrução de outras harts observem os stores da hart local. Para tornar um store em memória de instruções visível a todas as harts, a hart que escreveu executa primeiro uma `FENCE` de dados e depois pede às harts remotas que executem `FENCE.I`. O manual acrescenta que a interface do ambiente de execução pode oferecer um mecanismo mais eficiente de sincronização do fluxo de instruções entre processadores.

## 5. Referências

| Item | Capítulo e seção do manual |
| :--- | :--- |
| Extensão e instrução `FENCE.I` | Capítulo 4, seção 4.1 |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
