# Sscofpmf: Fragmento de Boot

O fragmento `src/Sscofpmf/boot.inc` limpa o estado de estouro dos contadores de eventos. O contrato de inclusão, a ordem e os registradores usados estão em [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Macro | `RV32_HAS_SSCOFPMF`, que o Core só aceita com `HAS_ZIHPM` e `HAS_INTERRUPTS` |
| Fonte | Volume II do manual do RISC-V (ISA privilegiada, versão 20260120), capítulo 14 e seções 3.1.9 e 3.1.10 |
| Registrador temporário | `t0` |

## 2. Estado deixado

| CSR | Valor | Motivo |
| :--- | :--- | :--- |
| `mhpmevent3h` a `mhpmevent31h` | 0 | Limpa o `OF` (bit 31), que sozinho só a escrita do programa zera, e o `MINH` (bit 30), de modo que a contagem no modo máquina fica ligada |
| `mip`, bit 13 (`LCOFIP`) | 0 | Um contador pode ter estourado antes de o fragmento do Zihpm zerar os seletores, e a pendência fica depois de o `OF` ser limpo |

O `LCOFIE`, bit 13 de `mie`, já foi zerado pelo fragmento do Zicsr. O fragmento do Sscofpmf vem depois do Zihpm, porque os seletores precisam estar em 0 antes de o `OF` ser limpo, e nenhum contador conta de novo.

## 3. Tamanho

São 31 instruções (124 bytes), 29 escritas de CSR, a máscara do bit 13 e a limpeza em `mip`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
