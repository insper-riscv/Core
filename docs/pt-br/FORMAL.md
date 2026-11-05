# Verificação formal

As provas formais do Core rodam no SymbiYosys sobre o netlist Verilog que o GHDL sintetiza de cada entidade, com as propriedades escritas em SystemVerilog em volta dele (`formal/*_props.sv`). Um mesmo conjunto de provas roda com mais de um engine, e o CI só aprova quando os engines que responderam concordam entre si e com o resultado esperado. Este documento descreve o que se prova, os engines, o arquivo de resultado e a regra que decide o check `formal`.

## 1. O que se prova

| Bloco | Propriedades | Tipos de prova |
| :--- | :--- | :--- |
| `csr_file` | `csr_file_props.sv` | indução, cover |
| `trap_unit` | `trap_unit_props.sv` | indução, cover, com e sem a verificação de endereço e o Zicclsm |
| `counter64` | `counter64_props.sv` | indução, cover, com larguras de 1 a 64 bits |
| `muldiv_fusion` | `muldiv_fusion_props.sv` | BMC, cover |
| `csr_file` com Zicntr | `csr_cntr_props.sv` | BMC, cover |
| `csr_file` com Zihpm | `csr_hpm_props.sv` | BMC, cover, com 29, 5, 4, 3 e 2 contadores reais e larguras de 0 a 64 bits |
| `zicond_unit` | `zicond_props.sv` | indução, cover |
| `zicond_decode` | `zicond_decode_props.sv` | indução, cover |

Cada defeito proposital do VHDL (um mutante) precisa fazer uma prova falhar, e esse resultado esperado é `fail`. Uma prova de indução ou de BMC espera `pass`, e um cover espera `pass` quando o objetivo é alcançável.

## 2. Engines

O engine é escolhido pela variável `FORMAL_ENGINE`.

| Engine | O que é | Indução | BMC | Cover | Tempo típico de `make formal` |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `bitwuzla` (padrão) | solver SMT para vetores de bits, pelo engine `smtbmc` | sim | sim | sim | cerca de 40 s |
| `boolector` | solver SMT para vetores de bits, pelo engine `smtbmc` | sim | sim | sim | cerca de 45 s |
| `yices` | solver SMT, pelo engine `smtbmc` | sim | sim | sim | cerca de 60 s |
| `abc-bmc3` | verificador de modelos limitado do ABC, pelo engine `abc bmc3` | não | sim | não | cerca de 35 s |

O `abc-bmc3` só verifica propriedades limitadas de projetos com registradores. Ele pula as provas de indução, os covers e os blocos combinacionais (o `trap_unit` e os blocos da Zicond, que o ABC recusa), o que deixa 55 das 92 provas sem resposta dele. Um pulo não é uma falha: é uma prova que o engine não faz.

Os tempos são de uma execução com 4 CPUs.

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

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../LICENSE).
