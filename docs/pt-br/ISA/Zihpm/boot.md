# Zihpm: Fragmento de Boot

O fragmento `src/Zihpm/boot.inc` deixa os 29 contadores de eventos sem evento escolhido e zerados. O contrato de inclusão, a ordem e os registradores usados estão em [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Macro | `RV32_HAS_ZIHPM` |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), capítulo 6, seção 6.2, e volume II, seções 2.1.1.10 e 2.1.1.12 |
| Registrador temporário | `t0` |

## 2. Estado deixado

| CSR | Valor | Motivo |
| :--- | :--- | :--- |
| `mhpmevent3` a `mhpmevent31` | 0 | O evento 0 não conta, e a aplicação escolhe o evento que quer medir |
| `mhpmcounter3` a `mhpmcounter31` | 0 | A medição parte do fim da BOOT |
| `mhpmcounter3h` a `mhpmcounter31h` | 0 | Metade alta dos mesmos contadores |
| `mcountinhibit`, bits 3 a 31 | 0 | Nenhum contador de eventos inibido. Os bits 0 a 2 são do Zicntr |

Os seletores são escritos antes dos contadores, de modo que nenhum contador conta durante a limpeza e um contador que o programa anterior deixou perto do estouro não estoura entre duas escritas. A liberação da inibição fica por último.

## 3. Núcleo com parte dos contadores

O Core implementa os `hpm_counters` primeiros contadores e responde aos 29 endereços de cada faixa. A escrita num índice sem contador é ignorada e a leitura vale zero, sem exceção, de modo que o fragmento escreve os 29 índices para qualquer `hpm_counters` e `hpm_width`. A escolha do Core para o contador não implementado está em [conformance.md](conformance.md).

## 4. Tamanho

São 89 instruções (356 bytes), 87 escritas de CSR, a máscara e a liberação da inibição. O fragmento repete a escrita com uma diretiva do montador, porque o endereço do CSR é um imediato da instrução e não admite laço em tempo de execução.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
