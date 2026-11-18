# Passo F.P10: porta tardia na escrita dos contadores de CSR

🌐 [Português](P10_ESCRITA_TARDIA_DOS_CONTADORES.md) · [English](../../en/timing/P10_ESCRITA_TARDIA_DOS_CONTADORES.md)

## 1. Resumo

| | |
| :--- | :--- |
| Problema | A habilitação de escrita da metade alta de `minstret` (e de `mcycle`, de `mcountinhibit` e do banco do Zihpm) saía do sinal de escrita válida compartilhado por todos os CSRs, com fanout de 293, e esse sinal esperava `pipe_run` (fanout 337), que vem da classificação do endereço de dados em MEM: dez níveis de lógica, com 1,2 e 1,8 ns de roteamento nos dois saltos de fanout alto, e 10,5 ns de dados num período de 10 ns |
| Mudança | O `csr_file` separa a escrita dos contadores em uma seleção cedo (endereço e efeito de escrita, ambos vindos de registradores) e uma porta tardia própria (`i_commit`, sem trap e sem `mret`), que entra na última camada de lógica e tem fanout só dos contadores |
| Efeito no comportamento | Nenhum: as habilitações valem as mesmas de antes em todos os ciclos |
| Efeito em ciclos por instrução | Nenhum |

## 2. Equivalência

Os endereços de `mcycle`, `mcycleh`, `minstret`, `minstreth` e `mcountinhibit` são sempre conhecidos e de leitura e escrita quando o perfil inclui Zicntr, então o teste de endereço conhecido e o de somente-leitura do decodificador geral são constantes verdadeiras nesses endereços. Para o banco do Zihpm, o endereço conhecido está contido na seleção do próprio banco, que já exige a faixa e o contador presente; o teste de somente-leitura continua feito fora do banco.

$$
we_{cntr} = commit \cdot \overline{trap} \cdot \overline{mret} \cdot write\_effect \cdot (addr = A_{cntr})
$$

## 3. Verificação

| Garantia | Verificação |
| :--- | :--- |
| As escritas, a retirada pendente e o cancelamento de `minstret` seguem iguais | Provas formais do `csr_file` e dos contadores, e testes de núcleo de Zicntr e Zihpm |
| O caminho deixou de ser crítico | Folga de setup do `csr_file` no Quartus, na tabela do pull request que trouxe esta mudança |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
