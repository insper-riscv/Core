# Zicclsm: O Que o RISC-V Exige

Fontes ([especificação de perfis do RISC-V](https://github.com/riscv/riscv-profiles) e [Load and Store Instructions](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html) do Capítulo 1 do manual).

A Zicclsm não faz parte do manual de ISA não privilegiada. Ela é definida na especificação de perfis do RISC-V, como um dos requisitos que um perfil impõe à memória principal. Este documento reúne o que essa especificação exige, o que o manual de ISA diz sobre acessos desalinhados em geral e como isso se relaciona com as exceções de endereço desalinhado. A implementação no Core está em [description.md](description.md).

## 1. Requisito do Perfil

### 1.1. Definição

A especificação de perfis define a Zicclsm como o requisito de que loads e stores desalinhados em regiões da memória principal que tenham os atributos de memória física (PMAs) de cacheabilidade e de coerência sejam suportados. O texto normativo diz apenas "misaligned loads and stores", sem qualificação, o que inclui os loads e stores comuns, escalares e vetoriais. O que conta como acesso desalinhado num load ou store vetorial é definido pela especificação de vetores.

### 1.2. Perfis Que a Exigem

| Perfil | Seção da especificação de perfis |
| :--- | :--- |
| RVA20U64 | RVA20U64 Mandatory Extensions |
| RVA22U64 | RVA22U64 Mandatory Extensions |
| RVA23U64 | RVA23U64 Mandatory Extensions |

Os perfis RVA20S64, RVA22S64 e RVA23S64 incluem todas as extensões não privilegiadas obrigatórias do perfil de usuário correspondente. A lista de novas extensões da especificação de perfis resume a Zicclsm como "Main memory supports misaligned loads/stores".

### 1.3. Notas Não Normativas

As notas que acompanham a definição não alteram o seu significado. Elas esclarecem os pontos abaixo.

| Ponto | Conteúdo da nota |
| :--- | :--- |
| Nome da extensão | A Zicclsm é um nome novo para uma característica já existente |
| Cobertura | O requisito vale para as instruções comuns de load e store, e não para AMOs nem para outras formas especializadas de acesso à memória |
| Desempenho | Um acesso desalinhado pode executar de forma extremamente lenta, e o software padrão deve supor a sua existência só por correção, nunca por desempenho |

## 2. O Que o Manual de ISA Diz Sobre Acessos Desalinhados

O volume de ISA não privilegiada trata do tema na seção Load and Store Instructions, do capítulo da base RV32I. Os pontos relevantes são os seguintes.

| Aspecto | Regra do manual |
| :--- | :--- |
| Acesso alinhado | Load ou store com endereço efetivo naturalmente alinhado nunca gera exceção de endereço desalinhado, independente do ambiente de execução (EEI) |
| Acesso desalinhado | O comportamento depende do EEI. O endereço é desalinhado quando não é divisível pelo tamanho do acesso em bytes |
| EEI que garante suporte | O software nunca vê uma exceção de desalinhamento, e o acesso pode ser tratado em hardware, por uma exceção invisível ao ambiente de execução, ou por uma combinação dos dois conforme o endereço |
| EEI que não garante suporte | O acesso pode completar ou gerar exceção. A exceção pode ser de endereço desalinhado ou de falha de acesso, e esta última é permitida quando o acesso não deve ser emulado, por exemplo se a região tem efeitos colaterais |
| Tipo de exceção | Quando o suporte não é garantido, o EEI define se a exceção é contida (tratável pelo software) ou fatal |
| Desempenho | Mesmo completando, o acesso desalinhado pode ser extremamente lento, por exemplo se for implementado por uma exceção invisível |
| Atomicidade | Loads e stores naturalmente alinhados são atômicos, e os desalinhados podem não ser, de modo que o software precisa de sincronização adicional quando exige atomicidade |

Para as regiões que cobre, a Zicclsm exige o suporte aos acessos desalinhados, o que corresponde ao caso do manual em que o EEI garante esse suporte.

## 3. Relação com as Exceções de Endereço Desalinhado

O manual de ISA privilegiada define os códigos de causa do registrador `mcause` para os acessos desalinhados, conforme a tabela de códigos de exceção da seção Machine Cause Register.

| Código | Causa |
| :--- | :--- |
| 4 | Load address misaligned |
| 6 | Store/AMO address misaligned |

Um acesso desalinhado que a implementação não executa gera uma dessas exceções, e o manual permite, no lugar da causa 4 ou 6, uma falha de acesso quando o acesso não deve ser emulado.

## 4. Escopo Considerado no Core

A especificação cobre loads e stores comuns, escalares e vetoriais, e exclui AMOs. O Core implementa os loads e stores escalares da RV32I (`LB`, `LBU`, `LH`, `LHU`, `LW`, `SB`, `SH` e `SW`), sem vetores e sem AMOs. O mapa que o Core adota como memória principal para esse fim está em [description.md](description.md).

## 5. Fontes

| Documento | Seção |
| :--- | :--- |
| RISC-V Profiles (repositório `riscv/riscv-profiles`, arquivos `profiles.adoc` e `rva23-profile.adoc`) | RVA20U64 Mandatory Extensions, RVA22U64 Mandatory Extensions, RVA23U64 Mandatory Extensions e a lista de novas extensões |
| Esclarecimento dos editores da especificação de perfis (issue 202 do mesmo repositório, fechada em 21/03/2026) | Texto normativo sem qualificação, com notas não normativas |
| The RISC-V Instruction Set Manual, Volume I (Unprivileged Architecture) | Capítulo RV32I Base Integer Instruction Set, seção Load and Store Instructions |
| The RISC-V Instruction Set Manual, Volume II (Privileged Architecture) | Machine-Level ISA, seção Machine Cause Register |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
