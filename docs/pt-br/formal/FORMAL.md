# Verificação formal

As provas formais do Core rodam no SymbiYosys sobre o netlist Verilog que o GHDL sintetiza de cada entidade, com as propriedades escritas em SystemVerilog em volta dele (`formal/*_props.sv`). Um mesmo conjunto de provas roda com mais de um engine, e o CI só aprova quando os engines que responderam concordam entre si e com o resultado esperado. Este documento descreve o que se prova, os engines, o arquivo de resultado e a regra que decide o check `formal`.

## 1. O que se prova

| Bloco | Propriedades | Tipos de prova |
| :--- | :--- | :--- |
| `csr_file` | `csr_file_props.sv` | indução, cover |
| `trap_unit` | `trap_unit_props.sv` | indução, cover, com e sem a verificação de endereço e o Zicclsm, e com a instrução ilegal antes do alvo desalinhado (Tabela 17) |
| `csr_file` com interrupções | `csr_irq_props.sv` | indução, BMC, cover, com a condição e a prioridade da tomada e os modos de `mtvec` |
| `trap_unit` com interrupção | `trap_unit_props.sv` | indução, cover |
| `stage_ex` com interrupções | `stage_ex_irq_props.sv` | indução, cover, com `mepc`, `mcause`, `MIE`, o PC seguinte e o efeito nulo do acesso a CSR abortado |
| `alu` | `alu_props.sv` | equivalência combinacional, cover |
| `trap_unit` com falhas de acesso | `trap_af_props.sv` | indução, cover, com os mutantes da ordem e do `mtval` |
| `csr_file` com `time_external` | `csr_time_props.sv` | BMC, cover |
| `counter64` | `counter64_props.sv` | indução, cover, com larguras de 1 a 64 bits, incluindo o pulso de estouro `o_wrap` |
| `muldiv_fusion` | `muldiv_fusion_props.sv` | BMC, cover |
| `csr_file` com Zicntr | `csr_cntr_props.sv` | BMC, cover |
| `csr_file` com Zihpm | `csr_hpm_props.sv` | BMC, cover, com 29, 5, 4, 3 e 2 contadores reais e larguras de 0 a 64 bits |
| `csr_file` com Sscofpmf | `csr_ofp_props.sv` | BMC, cover, com `OF`, `MINH`, `LCOFIP`, `LCOFIE` e a prioridade do timer sobre o estouro, em um índice simbólico |
| `zicond_unit` | `zicond_props.sv` | indução, cover |
| `zicond_decode` | `zicond_decode_props.sv` | indução, cover |
| `core` com Zicsr (`o_trap_take`) | `core_trap_take_props.sv` | BMC, cover |

Cada defeito proposital do VHDL (um mutante) precisa fazer uma prova falhar, e esse resultado esperado é `fail`. Uma prova de indução ou de BMC espera `pass`, e um cover espera `pass` quando o objetivo é alcançável.

## 2. Engines

O engine é escolhido pela variável `FORMAL_ENGINE`.

| Engine | O que é | Indução | BMC | Cover | Tempo típico de `make formal` |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `bitwuzla` (padrão) | solver SMT para vetores de bits, pelo engine `smtbmc` | sim | sim | sim | 216 s |
| `boolector` | solver SMT para vetores de bits, pelo engine `smtbmc` | sim | sim | sim | 226 s |
| `yices` | solver SMT, pelo engine `smtbmc` | sim | sim | sim | 376 s |
| `abc-bmc3` | verificador de modelos limitado do ABC, pelo engine `abc bmc3` | não | sim | não | 346 s |

O `abc-bmc3` só verifica propriedades limitadas de projetos com registradores. Ele pula as provas de indução, os covers e os blocos combinacionais (a `alu`, o `trap_unit` e os blocos da Zicond, que o ABC recusa), o que deixa 53 das 154 provas sem resposta dele. Um pulo não é uma falha: é uma prova que o engine não faz. As provas de indução do `mip`, do `mie` e do `mstatus.MIE` têm por isso uma forma limitada de 6 ciclos a mais (`csri_bounded`), a única que ele responde.

Os tempos são de uma execução com 4 CPUs e 8 GB, numa estação de laboratório com outros jobs em paralelo.

## 3. Rodando

```bash
make formal                          # engine padrão (bitwuzla)
make formal FORMAL_ENGINE=yices      # outro engine
FORMAL_TIMEOUT=300 make formal       # limita cada prova a 300 s (900 s por padrão)
```

O script `formal/run.sh` classifica o código de saída do `sby` por prova.

| Código do `sby` | Veredito | Significado |
| :---: | :--- | :--- |
| 0 | `pass` | a propriedade vale (ou o cover é alcançável) |
| 2 | `fail` | há um contraexemplo (ou o cover é inalcançável) |
| outro | `error` | a ferramenta não chegou a um veredito: tempo esgotado (124), erro (16) ou desconhecido (4) |
| | `skip` | o engine não faz esse tipo de prova |

Um `error` reprova a execução do engine, mesmo quando o veredito esperado é `fail`, para que um engine quebrado não passe por um mutante pego.

## 4. Arquivo de resultado

Cada execução grava `build/formal/result-<engine>.tsv`, uma linha por prova, com colunas separadas por tabulação.

| Coluna | Conteúdo |
| :---: | :--- |
| 1 | identificador da prova (o mesmo em todos os engines) |
| 2 | veredito esperado (`pass` ou `fail`) |
| 3 | veredito do engine (`pass`, `fail`, `error` ou `skip`) |
| 4 | código de saída do `sby` |
| 5 | tempo da prova em milissegundos |
| 6 | descrição da prova |

## 5. O agregador

O script `formal/aggregate.sh <diretório>` lê todos os `result-<engine>.tsv` do diretório e decide, por prova, a partir dos vereditos `pass` e `fail`. Um `error` e um `skip` não contam como resposta.

| Situação da prova | Resultado |
| :--- | :--- |
| nenhum engine respondeu | reprova |
| um engine disse `pass` e outro disse `fail` | reprova (os engines discordam) |
| os engines que responderam concordam, mas diferem do esperado | reprova |
| os engines que responderam concordam com o esperado | passa |

Um engine que não gravou resultado conta como `error` em todas as provas. O agregador sai com código 1 se alguma prova reprova ou se não há nenhum arquivo de resultado, e escreve a tabela de provas por engines na saída e no resumo do job do GitHub Actions.

Os testes do agregador rodam com `bash formal/aggregate_test.sh`.

## 6. No CI

O workflow tem um job por engine, `formal - <engine>` (`yices`, `bitwuzla`, `boolector` e `abc-bmc3`), que roda `make formal FORMAL_ENGINE=<engine>` e sobe o resultado e os logs como artefato. O job `formal` espera todos eles, baixa os artefatos e roda o agregador. Só o job `formal` é check obrigatório do ruleset da branch padrão, então um engine que quebra não bloqueia o merge enquanto outro decide, e um contraexemplo achado por qualquer engine bloqueia. Num push para a `main` que reaproveita o resultado de um PR já aprovado, os engines e o `formal` são pulados juntos, como os demais checks obrigatórios.

## 7. Aviso é erro

Qualquer aviso do GHDL, do Yosys ou do SymbiYosys faz o `formal/run.sh` falhar, nas provas e nos mutantes. A guarda fica em `formal/warnings.sh`: o script varre a saída de cada ferramenta depois que ela termina e, para cada linha com a palavra `warning` (sem diferenciar maiúsculas, palavra inteira ou no plural), imprime `formal: WARNING treated as error: <arquivo>:<linha>:<texto>` e reprova a execução ao final. Nomes como `warning_count` e o resumo `Warnings: 0` do Yosys não contam.

Um aviso indica código fora da norma ou no limite, então a correção é no VHDL ou nas propriedades, nunca em uma opção que esconda o aviso (`-Wno-*`). Cada mutante é analisado no lugar da unidade que substitui, de modo que nenhuma entidade é definida em dois arquivos.

O engine `abc-bmc3` tem uma exceção exata, só para as mensagens que o próprio ABC imprime ao ler o arquivo AIGER recebido (a contagem de saídas lidas como restrições, que são as suposições e o clock do passo `clk2ff`, e `The network has no constraints.`), e só no log desse engine. Os avisos de que o clock é um bit sem driver não são aceitos: o script da prova achata o projeto e elimina os apelidos do clock antes de o arquivo AIGER ser escrito. Uma mensagem a mais, `The network is combinational.`, é aceita apenas na prova que o engine recusa por ser combinacional e que o script registra como `skip`. O `yices`, o `bitwuzla` e o `boolector` não têm exceção, e qualquer outro aviso do `abc-bmc3` continua falhando.

Os testes da guarda rodam junto com os do agregador, em `bash formal/aggregate_test.sh`.

## 8. Provas de interrupção por indução

Uma propriedade que guarda um modelo de um registrador da unidade fora dela não se prova por indução sozinha, porque a indução parte de qualquer estado da unidade e o modelo é livre. A correção é uma invariante que diz que o modelo é o registrador. O `formal/run.sh` liga fios de `props` a redes da netlist achatada (`PROBES`, comando `connect` do Yosys), sem alterar o VHDL, e a prova afirma, a cada ciclo sem reset, que o modelo é o registrador.

| Prova | Registradores ligados | Propriedade por indução |
| :--- | :--- | :--- |
| `csri_safety` | máscaras de `mie`, `mstatus.MIE` e `MPIE`, BASE e MODE de `mtvec` | `mip` lê as três linhas nas posições 3, 7 e 11, `mie` guarda só esses bits, escrever em `mip` não muda nada, `o_irq_pending` é linhas e máscara, `o_irq_take` exige `mstatus.MIE`, a causa tem prioridade externa, software, timer, e `mtvec` guarda BASE e MODE |
| `csrio_safety` | os mesmos | sem `has_interrupts` as linhas são ignoradas e `mip` e `mie` leem zero |

A tomada em si é provada pelo `stage_ex_irq_props.sv` e pelo `trap_unit_props.sv` (ambos por indução): `mepc` é o endereço da instrução abortada, `mcause` leva a causa e a linha, `MIE` vai a 0 e `MPIE` a 1, o PC seguinte é BASE ou o vetor, e a interrupção vence toda exceção e o `MRET`. A restauração de `MIE` pelo `MRET` é provada por indução em `csr_mstatus`. As provas de contadores (`csr_cntr_props.sv`, `csr_hpm_props.sv`) e a fusão continuam limitadas, e o motivo está nos comentários de cada arquivo.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
