# 3. Relógios e Reset (contrato K7)

## 1. Escopo

O SoC pede relógios por papel e nunca por saída de PLL. Este contrato define os papéis, de onde vem o valor de cada um e quando o reset termina. Quem liga um papel a uma saída do PLL é o topo gerado da placa, e nenhum módulo do SoC cita PLL, família de FPGA nem placa. Os contratos de barramento e de memória ([02-barramento-e-memoria.md](02-barramento-e-memoria.md) e o contrato de memória do repositório Memory) valem dentro de cada papel.

## 2. Papéis de relógio

| Papel | Uso | Origem do valor |
| :--- | :--- | :--- |
| `core` | Núcleo e memórias de dados | `platform.yaml`, `clocks.core` |
| `fetch` | Memórias de instrução | `platform.yaml`, `clocks.fetch`, com fase relativa a `core` |
| `mem` | Controlador de dispositivo | `platform.yaml` ou o limite do chip, o menor dos dois |
| `mem_pin` | Relógio que sai pelo pino do chip | Fase vinda do chip e da placa |
| `rst` | Reset do SoC, ativo em `'1'` | Topo gerado |

Um módulo recebe uma porta de relógio para cada papel que usa, nomeada com o papel (por exemplo `i_clk_core`), e as frequências e fases chegam a ele só pelo topo. O valor de um papel é a frequência pedida ao PLL, de modo que um módulo nunca assume um número de megahertz.

## 3. Reset

O reset `rst` vale `'1'` enquanto o PLL não travou e é liberado depois do travamento. A latência do reset, em função do instante de travamento $t_{lock}$ e do período $T_{core}$ do papel `core`, é

$$ t_{rst} = t_{lock} + 2\,T_{core} $$

Os dois ciclos de `core` depois do travamento dão tempo de o reset chegar a todos os registradores antes do primeiro pedido do núcleo.

## 4. Travessia entre papéis

Um sinal que sai de um papel e entra em outro cruza o domínio por inversão de sinal e dois flip-flops de sincronização, como descreve a seção 4 do contrato de memória. O contrato não admite um sinal de controle lido num domínio que não é o seu sem essa sincronização.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
