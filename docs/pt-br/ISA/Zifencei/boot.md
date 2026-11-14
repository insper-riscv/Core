# Zifencei: Fragmento de Boot

O fragmento `src/Zifencei/boot.inc` executa `fence.i`, para a busca de instruções enxergar tudo o que a inicialização gravou. O contrato de inclusão, a ordem e os registradores usados estão em [04-contrato-de-boot.md](../../contracts/04-contrato-de-boot.md).

## 1. Referência

| Item | Valor |
| :--- | :--- |
| Macro | `RV32_HAS_ZIFENCEI` |
| Fonte | Volume I do manual do RISC-V (ISA não privilegiada, versão 20260120), capítulo 4 |
| Registrador temporário | Nenhum |

## 2. Estado deixado

Nenhum CSR muda. O `fence.i` é a última instrução de inicialização da BOOT, de modo que a busca seguinte, a do salto para a aplicação, já enxerga a memória como a inicialização a deixou.

Num núcleo sem Zifencei o `fence.i` é uma instrução ilegal, por isso o fragmento só gera a instrução com `RV32_HAS_ZIFENCEI`. Quando o núcleo não tem cache de instruções nem janela externa de instrução, o `fence.i` não tem efeito e a plataforma pode dispensar a extensão. O comportamento da instrução no pipeline está em [description.md](description.md).

## 3. Tamanho

É 1 instrução (4 bytes).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
