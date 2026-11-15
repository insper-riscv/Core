# Zicntr: Fragmento de Boot

O fragmento `src/Zicntr/boot.inc` zera os contadores de máquina e os deixa contando. O contrato de inclusão, a ordem e os registradores usados estão em [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Macro | `RV32_HAS_ZICNTR` |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), capítulo 6, seção 6.1, e volume II, seções 2.1.1.10 e 2.1.1.12 |
| Registrador temporário | Nenhum |

## 2. Estado deixado

| CSR | Valor | Motivo |
| :--- | :--- | :--- |
| `mcycle` e `mcycleh` | 0 | A contagem de ciclos da aplicação parte do fim da BOOT |
| `minstret` e `minstreth` | 0 | A contagem de instruções parte do fim da BOOT |
| `mcountinhibit`, bits 0 e 2 | 0 | Os dois contadores correm. Os bits 3 a 31 são do Zihpm |

Os dois contadores são inibidos durante a escrita das metades, para a metade baixa não avançar entre uma escrita e a outra, e liberados no fim.

O `mcounteren` não é escrito, porque o Core só tem o modo M e o registrador não existe. O `time` é somente leitura e pertence à plataforma.

## 3. Tamanho

São 6 instruções (24 bytes), sem registrador temporário.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
