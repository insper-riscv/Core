# Zicsr: Fragmento de Boot

O fragmento `src/Zicsr/boot.inc` deixa o estado de máquina sem interrupção habilitada nem pendente e com um tratador de trap seguro. O contrato de inclusão, a ordem e os registradores usados estão em [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Macro | `RV32_HAS_ZICSR`, com `RV32_HAS_INTERRUPTS` para o `mip` |
| Fonte | Volume II do manual do RISC-V (ISA privilegiada, versão 20260120), seções 2.1.1.6, 2.1.1.7, 2.1.1.9 e 2.1.1.13 |
| Registrador temporário | `t0` |
| Símbolo externo | `rv32_boot_trap`, definido por quem inclui, alinhado a 4 bytes |

## 2. Estado deixado

| CSR | Valor | Motivo |
| :--- | :--- | :--- |
| `mstatus` | 0 | `MIE` em 0 desliga as interrupções globais, e `MPIE` em 0 impede que um `mret` as reabra |
| `mie` | 0 | Nenhuma fonte de interrupção habilitada, inclusive o `LCOFIE` do Sscofpmf |
| `mscratch` | 0 | Valor conhecido para o primeiro uso pelo tratador da aplicação |
| `mtvec` | Endereço de `rv32_boot_trap`, `MODE` direto | O endereço é múltiplo de 4, de modo que os bits 1 e 0 valem 0 e todo trap vai ao tratador seguro |
| `mip` | 0, só com `RV32_HAS_INTERRUPTS` | O programa só escreve os bits que o hart deixa escrever, os demais espelham a plataforma |

Com `RV32_HAS_ACCESS_FAULTS` não há nada a mais a inicializar, porque o `mtvec` já cobre o trap de falha de acesso.

## 3. Tamanho

São 6 instruções (24 bytes) e 7 (28 bytes) com `RV32_HAS_INTERRUPTS`. O endereço do tratador é formado em relação ao `pc`, o que independe do endereço em que a BOOT é montada.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
