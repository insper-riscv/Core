# Passo F.P1: exceção de acesso decidida em MEM

## 1. Resumo

| | |
| :--- | :--- |
| Problema | A exceção de endereço de um load ou store (desalinhamento fora da memória principal) dependia do resultado da ULA, e o sinal de tomada de trap seguia dali até o PC, os registradores de barreira, os CSRs e a escrita da RAM |
| Mudança | Com Zicsr, a unidade de traps do estágio EX não confere o endereço efetivo; quem o confere é a do estágio MEM, sobre o endereço registrado em EX/MEM |
| Efeito no comportamento | A exceção é tomada um estágio depois, mas de uma instrução mais antiga que a de EX, então o trap continua preciso |
| Efeito no laço do núcleo | Os trechos de detecção de exceção e de limpeza (7,3 ns de um laço de 18,9 ns) saem do caminho da ULA |
| Sem Zicsr | O estágio EX continua conferindo o endereço e só sinaliza a causa, porque não há CSR para registrá-la nem redirecionamento |

## 2. Caminho antes e depois

| Etapa | Antes | Depois |
| :--- | :--- | :--- |
| Origem do endereço conferido | Saída combinacional da ULA em EX | Registrador `r_alu_out` de EX/MEM |
| Quem decide | `trap_unit` de EX com `check_ea` ligado | `trap_unit` de MEM com `check_ea` ligado; a de EX recebe `check_ea` desligado |
| Cadeia depois da ULA | ULA, comparação de região e de cruzamento de palavra, junção das causas, limpeza do pipeline | Nenhuma: a ULA termina no registrador EX/MEM |
| Cadeia no ciclo seguinte | Não existe | Comparação de região e de cruzamento de palavra sobre o registrador, junção das causas, limpeza do pipeline |

## 3. Garantias e como são verificadas

| Garantia | Verificação |
| :--- | :--- |
| O load ou store que falha não acessa a memória nem escreve o destino | Teste `CoreMisalignedHalf` (loads sem efeito no registrador, stores sem efeito no buffer) |
| A instrução seguinte, que já está em EX, não confirma CSR, não escreve registrador nem memória e não conta desvio tomado | Teste `CoreMemTrapEx`, oito casos (load ou store que falha, seguido de escrita de CSR, store, escrita de registrador ou desvio tomado) |
| `mepc` guarda o PC da instrução que falhou, `mcause` e `mtval` trazem a causa e o endereço | Teste `CoreMemTrapEx` |
| `minstret` e os contadores do Zihpm não contam a instrução que falhou nem a descartada | Teste `CoreMemTrapEx` (diferença de `minstret` igual a uma instrução mais as do tratador) e mutante `cntr_cancel_ignored` da prova formal do `csr_file` |
| Cada causa e cada região da `trap_unit` | Provas formais da `trap_unit`, com e sem a conferência de endereço, e com o Zicclsm ligado e desligado |

O teste `CoreMemTrapEx` falha nos oito casos quando o descarte da instrução de EX é removido (a validade de EX deixa de descontar o trap de MEM).

## 4. Medição

Compilação da `de0-cv` (perfil completo, 29 contadores do Zihpm) com o RTL deste passo, no Quartus Prime 25.1 Lite, modo `HIGH PERFORMANCE EFFORT`, sementes 1 a 5, relógio do núcleo em 50 MHz, modelo lento a 85 °C. As fontes são Insper-RISC-V `224a762`, Core `8a828cc`, Memory `1160ae1`, Peripherals `d7253f6` e Common-Components `9aa6a75`; os arquivos de resultado estão em `docs/pt-br/platform/timing/dados/` do Insper-RISC-V.

| Par de relógios | Pior folga das cinco sementes (ns) | Atraso de dados do pior caminho (ns) |
| :--- | ---: | ---: |
| núcleo para núcleo | 3,931 | 14,6 a 16,7 |
| núcleo para busca | 3,403 | 7,9 a 9,2 |
| busca para núcleo | -1,345 | 4,9 a 5,2 |

| Domínio | Folga de setup, pior semente (ns) | Fmax, pior semente (MHz) |
| :--- | ---: | ---: |
| Núcleo | -1,345 | 62,23 |
| Busca | 3,403 | |
| Controlador da SDRAM | -0,744 | 173,28 |
| `DRAM_CLK` | -0,127 | |
| JTAG | 7,612 | 55,22 |

A folga de hold no modelo rápido a 0 °C é positiva em todos os domínios e sementes, com o mínimo de 0,002 ns no JTAG. Os ALMs ficam em 8.058 a 8.095 (44 %).

O laço do núcleo (`EX/MEM r_alu_out` e dos CSRs até o PC, os registradores de barreira e os contadores) deixou de ser o limite: a folga a 50 MHz é positiva em todas as sementes. O limite é o caminho da etiqueta da cache de instruções até o PC (busca para núcleo), que o passo F.P5 ataca. O pior caminho do núcleo para o núcleo nasce em `ID/EX r_imm`, atravessa o multiplexador de leitura dos CSRs (29 contadores de eventos) e termina no `mepc`, ou seja, a leitura de CSR realimenta a escrita de CSR por 9 níveis de lógica.

## 5. Custo em ciclos por instrução

Nenhum. A exceção de acesso só ocorre em programas que falham, e o caminho sem exceção tem a mesma latência.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
