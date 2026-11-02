# Zicsr: Instruções da Extensão

Este documento resume o que o manual do RISC-V exige da extensão `Zicsr` (instruções de acesso a registradores de controle e estado, CSRs). A referência é o manual de ISA não privilegiada v20260120, Capítulo 5, "Zicsr" Extension for Control and Status Register (CSR) Instructions, Version 2.0, seção 5.1 e suas subseções. A implementação no Core está em [description.md](description.md).

## 1. Escopo da Extensão

Cada hart tem um espaço de endereços de CSR próprio, com 4096 registradores (manual, seção 5.1). As instruções da extensão são as únicas que acessam esse espaço de forma explícita. Os contadores e temporizadores deixaram de ser obrigatórios na base, e suas instruções de acesso passaram do RV32I para este capítulo.

## 2. Instruções

### 2.1. Formato e Codificação

As seis instruções usam o opcode `SYSTEM` (`1110011`). O campo `csr` ocupa os bits 31 a 20, e as formas imediatas guardam um valor de 5 bits, estendido com zeros, no campo `rs1` (manual, seção 5.1.1). A codificação completa consta na listagem de instruções do Capítulo 35, "RV32/64G Instruction Set Listings".

| Instrução | Bits 31 a 20 | Bits 19 a 15 | Bits 14 a 12 (`funct3`) | Bits 11 a 7 | Bits 6 a 0 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| `CSRRW` | `csr` | `rs1` | `001` | `rd` | `1110011` |
| `CSRRS` | `csr` | `rs1` | `010` | `rd` | `1110011` |
| `CSRRC` | `csr` | `rs1` | `011` | `rd` | `1110011` |
| `CSRRWI` | `csr` | `uimm[4:0]` | `101` | `rd` | `1110011` |
| `CSRRSI` | `csr` | `uimm[4:0]` | `110` | `rd` | `1110011` |
| `CSRRCI` | `csr` | `uimm[4:0]` | `111` | `rd` | `1110011` |

### 2.2. Semântica

Cada instrução lê e modifica atomicamente um único CSR. Seja $C$ o valor antigo do CSR, $S$ o operando de origem (o valor de `rs1` nas formas por registrador e `uimm` nas formas imediatas) e $C'$ o valor novo.

| Instrução | Valor escrito em `rd` | Novo valor do CSR |
| :--- | :--- | :--- |
| `CSRRW`, `CSRRWI` | $C$ estendido com zeros até `XLEN` | $C' = S$ |
| `CSRRS`, `CSRRSI` | $C$ | $C' = C \lor S$ (cada bit 1 de $S$ liga o bit correspondente, se ele for gravável) |
| `CSRRC`, `CSRRCI` | $C$ | $C' = C \land \lnot S$ (cada bit 1 de $S$ desliga o bit correspondente, se ele for gravável) |

Um bit que lê um valor diferente do que armazena pode mudar numa `CSRRS` ou `CSRRC` mesmo sem ter sido selecionado por $S$ (o manual cita um bit de `pmpaddr` como exemplo).

### 2.3. Leitura e Escrita Condicionais

Os registradores usados como `rd`, `rs1` ou `uimm` decidem se a instrução lê e se escreve o CSR (manual, Tabela 1 da seção 5.1.1).

| Instrução | Condição | Lê o CSR | Escreve o CSR |
| :--- | :--- | :---: | :---: |
| `CSRRW` | `rd = x0` | Não | Sim |
| `CSRRW` | `rd ≠ x0` | Sim | Sim |
| `CSRRS`, `CSRRC` | `rs1 = x0` | Sim | Não |
| `CSRRS`, `CSRRC` | `rs1 ≠ x0` | Sim | Sim |
| `CSRRWI` | `rd = x0` | Não | Sim |
| `CSRRWI` | `rd ≠ x0` | Sim | Sim |
| `CSRRSI`, `CSRRCI` | `uimm = 0` | Sim | Não |
| `CSRRSI`, `CSRRCI` | `uimm ≠ 0` | Sim | Sim |

Regras complementares do manual:

- `CSRRS` e `CSRRC` com `rs1 = x0`, assim como `CSRRSI` e `CSRRCI` com `uimm = 0`, não escrevem o CSR. Elas não produzem efeitos colaterais de escrita e não geram exceção de instrução ilegal em CSRs somente leitura.
- `CSRRS` e `CSRRC` sempre leem o CSR e disparam os efeitos colaterais de leitura, quaisquer que sejam `rd` e `rs1`.
- Se `rs1` não é `x0` mas contém zero, não há efeitos colaterais por campo, e os efeitos de escrever o CSR inteiro continuam valendo.
- `CSRRW` com `rs1 = x0` escreve zero no CSR.

### 2.4. Atomicidade e Efeitos Colaterais

A leitura e a escrita de uma instrução formam uma única operação indivisível sobre o CSR. Os efeitos colaterais de escrita seguem a regra abaixo (manual, seção 5.1.1).

| Operação | Campos que sofrem efeitos colaterais de escrita |
| :--- | :--- |
| `CSRRW`, `CSRRWI` | Todos os campos do CSR escrito |
| `CSRRS`, `CSRRSI`, `CSRRC`, `CSRRCI` | Só os campos que têm algum bit 1 em `rs1` ou `uimm` |

Os CSRs padrão não têm efeitos colaterais de leitura e, na data do manual, nenhum tem efeitos colaterais por campo, de modo que o efeito de um acesso a CSR padrão decorre só do opcode. Definir CSRs com efeitos colaterais por campo é desencorajado. Consequências que ocorrem apenas porque o CSR passou a ter certo valor, como um trap provocado pelo novo estado, são efeitos indiretos e não efeitos colaterais.

Para um contador que o hardware atualiza durante a execução (por exemplo `instret`), a leitura explícita devolve o valor anterior à instrução, a escrita explícita substitui a atualização do hardware naquela instrução e o valor escrito é o que a instrução seguinte lê.

### 2.5. Pseudoinstruções

| Pseudoinstrução | Expansão |
| :--- | :--- |
| `CSRR rd, csr` | `CSRRS rd, csr, x0` |
| `CSRW csr, rs1` | `CSRRW x0, csr, rs1` |
| `CSRWI csr, uimm` | `CSRRWI x0, csr, uimm` |

O manual também define `CSRS`, `CSRC`, `CSRSI` e `CSRCI` para os casos em que o valor antigo não é necessário.

### 2.6. Ordenação dos Acessos

Conforme a seção 5.1.1.1 do manual, "CSR Access Ordering":

- Um hart observa seus próprios acessos a CSR na ordem do programa, inclusive os implícitos. A leitura explícita devolve o estado anterior à instrução, a escrita explícita suprime e sobrepõe escritas implícitas da mesma instrução, e a instrução seguinte já vê todas as consequências.
- Pelo modelo de memória (RVWMO), os acessos a CSR são fracamente ordenados em relação a outros harts e dispositivos, e não são ordenados em relação a acessos explícitos à memória, salvo dependências sintáticas, regras do atributo de ordenação de memória da plataforma ou efeito sobre a execução do acesso à memória.
- O software impõe outras ordens com `FENCE`. Para essa finalidade, a leitura de CSR conta como entrada de dispositivo (`I`) e a escrita como saída de dispositivo (`O`).
- Uma plataforma pode declarar certos CSRs fortemente ordenados.

## 3. Espaço de Endereços de CSR

O manual não privilegiado fixa só o campo de 12 bits (4096 endereços). As convenções de acesso vêm do manual de arquitetura privilegiada, Capítulo 1, seção 1.1.1, "CSR Address Mapping Conventions".

| Bits do endereço | Significado |
| :--- | :--- |
| `[11:10]` | Tipo de acesso; `00`, `01` e `10` indicam leitura e escrita, e `11` indica somente leitura |
| `[9:8]` | Menor nível de privilégio que acessa o CSR (`00` usuário, `01` supervisor, `11` máquina; o padrão `10` aparece nos CSRs de hipervisor) |

Os efeitos de uma violação, segundo o mesmo manual, são os seguintes.

| Situação | Resultado |
| :--- | :--- |
| Escrita num CSR somente leitura | Exceção de instrução ilegal |
| Privilégio insuficiente | Exceção de instrução ilegal (ou de instrução virtual, nos casos de hipervisor) |
| CSR inexistente | A instrução é reservada; o texto consultado não nomeia a exceção |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
