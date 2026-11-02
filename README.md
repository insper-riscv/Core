# Core

🌐 [Português](README.md) · [English](README.en.md)

Núcleo do processador RISC-V RV32 em VHDL-2008 organizado com uma pipeline de 5 estágios (IF, ID, EX, MEM e WB), modularizado por extensão da ISA (`I`, `M`, `Zicsr` e `Zifencei`) sob a entidade de topo (`core`), acompanhado de testes unitários por entidade via cocotb/GHDL e de verificação formal via SymbiYosys.

## 1. Documentação

- [AUTHORS.md](AUTHORS.md): autores com commits no repositório, com nome e conta do GitHub.
- [CONTRIBUTING.md](CONTRIBUTING.md): regras obrigatórias de contribuição, norma VHDL-2008 (`--std=08`), convenção de nomenclatura, prefixos `i_`/`o_`, cabeçalhos, docstrings e regras de documentação.
- [ISA/I/instructions.md](docs/pt-br/ISA/I/instructions.md): requisitos do manual do RISC-V para a base RV32I (estado do programador, formatos, as 37 instruções com codificação e semântica, `FENCE`, `ECALL`, `EBREAK`) e o comportamento do Core em cada caso.
- [ISA/I/description.md](docs/pt-br/ISA/I/description.md): implementação da base RV32I no Core, com estágios, decodificador de controle, ULA, extensores de imediato e de leitura, gerenciador de stores, adiantamento e hazards.
- [ISA/I/construcao-incremental.md](docs/pt-br/ISA/I/construcao-incremental.md): formatos das instruções de 32 bits do RISC-V e progressão incremental do caminho de dados para as 37 instruções da base RV32I.
- [ISA/I/ULA.md](docs/pt-br/ISA/I/ULA.md): código de operação, somador-subtrator compartilhado, desvios, deslocadores e seleção do resultado da ULA.
- [ARCHITECTURE.md](docs/pt-br/ARCHITECTURE.md): microarquitetura do pipeline de 5 estágios, responsabilidades por estágio, caminhos de forwarding, detecção de hazard load-use, stall, flush e suporte às extensões `M`, `Zicsr` e `Zifencei`.
- [PIPELINE_ARCHITECTURE_GUIDE.md](docs/pt-br/PIPELINE_ARCHITECTURE_GUIDE.md): referência detalhada dos sinais de interconexão entre os estágios, barreiras síncronas (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`), equações de stall e flush e resolução de desvios.
- [ISA/I/DECODER.md](docs/pt-br/ISA/I/DECODER.md): tabela de decodificação da unidade de controle base, com os sinais de controle das 37 instruções da base RV32I e o comportamento de qualquer outra instrução como `NOP`.
- [contracts/01-contrato-de-extensao.md](docs/pt-br/contracts/01-contrato-de-extensao.md): contrato de diretórios por extensão, manifestos de perfil (`profiles/*.yaml`) e ponto único de integração de novas extensões na entidade de topo.
- [contracts/02-barramento-e-memoria.md](docs/pt-br/contracts/02-barramento-e-memoria.md): protocolo de barramento de instruções e de dados (endereçamento em byte, habilitação por byte, handshake de espera por memória lenta e cache de instruções).
- [ISA/Zicclsm/instructions.md](docs/pt-br/ISA/Zicclsm/instructions.md) e [ISA/Zicclsm/description.md](docs/pt-br/ISA/Zicclsm/description.md): o que a especificação de perfis exige da Zicclsm e a execução em hardware dos loads e stores desalinhados, classificação dos acessos, regiões cobertas em cada mapa de memória e o acesso em duas etapas que cruza a palavra.
- [FORMAL.md](docs/pt-br/FORMAL.md): provas formais, engines de solver, arquivo de resultado por engine e a regra do agregador que decide o check `formal` do CI.
- [ISA/E/description.md](docs/pt-br/ISA/E/description.md): o genérico `num_regs` que escolhe o banco de 32 registradores (RV32I) ou de 16 (RV32E), a instrução ilegal com `x16` a `x31` e a ABI `ilp32e`.
- [ISA/Zicsr/instructions.md](docs/pt-br/ISA/Zicsr/instructions.md) e [ISA/Zicsr/description.md](docs/pt-br/ISA/Zicsr/description.md): extensão Zicsr, com as instruções, a codificação e as regras de leitura e escrita exigidas pelo manual, e a implementação no Core (banco de CSRs, exceções síncronas, `MRET`, redirecionamento e comportamento sem Zicsr).
- [ISA/Zicntr](docs/pt-br/ISA/Zicntr/description.md): contadores básicos `cycle`, `time` e `instret` (Zicntr), com o que o manual exige, o bloco contador de 64 bits, a retirada de instruções, o divisor de tick e o `mcountinhibit`.
- [ISA/Zihpm](docs/pt-br/ISA/Zihpm/description.md): contadores de desempenho `hpmcounter` (Zihpm), com o que o manual exige, a organização dos contadores de eventos, a regra de contagem e a tabela de eventos.
- [ISA/M/instructions.md](docs/pt-br/ISA/M/instructions.md): instruções da extensão `M` conforme o manual do RISC-V (capítulo 11): codificação, divisão, divisão por zero e estouro.
- [ISA/M/description.md](docs/pt-br/ISA/M/description.md): como o Core executa a `M`: decodificador, divisor não-restaurador, parada do pipeline, fusão de pares e verificação formal.
- [ISA/Zmmul/instructions.md](docs/pt-br/ISA/Zmmul/instructions.md): instruções da extensão `Zmmul` (só multiplicação, seção 11.1.3 do manual): codificação e semântica.
- [ISA/Zmmul/description.md](docs/pt-br/ISA/Zmmul/description.md): como o Core executa a `Zmmul`: configuração, decodificação sem divisão e multiplicador de Booth.
- [ISA/Zifencei/instructions.md](docs/pt-br/ISA/Zifencei/instructions.md) e [ISA/Zifencei/description.md](docs/pt-br/ISA/Zifencei/description.md): extensão Zifencei (`FENCE.I`), exigências do manual, regiões que passam pela cache de instruções, execução com e sem cache de dados write-back, efeito no pipeline e nas caches e custo.
- [LARGURA_DA_MEMORIA.md](docs/pt-br/LARGURA_DA_MEMORIA.md): regras do adaptador entre a palavra de 32 bits do Core e uma memória mais estreita ou mais larga, com endereço, máscara de bytes, leitura, sinal de pronto e interação com o acesso desalinhado.
- [bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md](docs/pt-br/bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md): análise matemática da faixa do resto parcial na divisão não-restauradora e do uso de 34 bits internos para divisores sem sinal acima de $2^{31}$.
- [bugs/FLUSH_COM_PIPELINE_PARADO.md](docs/pt-br/bugs/FLUSH_COM_PIPELINE_PARADO.md): análise da interação entre redirecionamento de desvio em EX e parada global do pipeline por espera de memória em MEM.
- [bugs/LOAD_EM_WB_DURANTE_STALL.md](docs/pt-br/bugs/LOAD_EM_WB_DURANTE_STALL.md): análise do load segurado em WB que era sobrescrito pelo load seguinte enquanto a unidade M para o pipeline.

## 2. Estrutura do Repositório

| Caminho | Conteúdo |
| :--- | :--- |
| `src/common/` | Submódulo [Common-Components](https://github.com/insper-riscv/Common-Components): os blocos genéricos (somador, flip-flop, registradores, multiplexadores e decodificador one-hot) que o Core importa |
| `src/shared/` | Peças do Core usadas por todos os perfis: pacotes de tipos e constantes, registradores de barreira entre estágios, unidade de controle base, banco de registradores, unidades de forwarding e hazard e gerador de PC |
| `src/I/` | Extensão inteira base RV32I, composta pela ULA, extensor de imediatos, extensor de leitura de memória e gerenciador de alinhamento de stores |
| `src/M/` | Extensão de multiplicação e divisão inteira RV32M, contendo decodificador dedicado, multiplicador sequencial de Booth radix-2, divisor não-restaurador de 34 bits e unidade integradora |
| `src/Zicsr/` | Extensão de registradores de controle e estado (CSRs) do modo máquina e unidade de detecção de exceções síncronas e retorno de trap (`MRET`) |
| `src/Zicntr/` | Extensão de contadores: `mcycle`, `minstret`, `time` e os espelhos `cycle`, `instret`, `time`, com o contador de 64 bits e o divisor do tempo |
| `src/Zicclsm/` | Unidade de acesso desalinhado à memória principal (`misaligned_unit`), que divide em duas etapas o acesso que cruza a palavra |
| `src/Zifencei/` | Extensão de sincronização da memória de instruções (`FENCE.I`), com suporte opcional a handshake de flush de cache de dados write-back |
| `src/core/` | Entidades dos 5 estágios do pipeline (`stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb`) e topo estrutural do processador (`core`) |
| `profiles/` | A especificação dos perfis (`matrix.yaml`) e os manifestos de fontes dos perfis que provam a compilação sem os diretórios opcionais (`rv32i.yaml`, `rv32i_zmmul.yaml`, `rv32im.yaml`, `rv32im_zicsr.yaml`, `rv32im_zicsr_zifencei.yaml`, `rv32im_zicclsm_zicntr_zifencei.yaml`) em ordem de dependência |
| `formal/` | Propriedades em SystemVerilog (`csr_file_props.sv`, `trap_unit_props.sv`), configurações `.sby`, script de verificação formal via GHDL + Yosys + SymbiYosys e o agregador dos engines ([documentação](docs/pt-br/FORMAL.md)) |
| `tests/python/` | Testes unitários por entidade e de integração do topo em cocotb/GHDL ([documentação](tests/python/README.md)) |

## 3. Perfis da ISA

O topo estrutural `core` recebe um generic booleano por extensão, que habilita ou desabilita a extensão em tempo de elaboração:

| Extensão | Generic | Padrão | Com o generic desligado |
| :--- | :--- | :--- | :--- |
| M | `has_m` | `false` | As instruções M comportam-se como `NOP` |
| Zmmul | `has_zmmul` | `false` | As instruções de multiplicação comportam-se como `NOP` |
| Zicsr | `has_zicsr` | `false` | Sem CSRs nem traps; o core sinaliza a exceção em `o_trap` |
| Zifencei | `has_zifencei` | `false` | `FENCE.I` comporta-se como `NOP` |
| Zicclsm | `has_zicclsm` | `true` | Todo acesso desalinhado gera trap |

Um perfil é uma combinação dessas extensões, e duas regras definem as combinações válidas: M e Zmmul nunca coexistem, porque M já inclui a multiplicação do Zmmul, e o core precisa de Zicsr ou de Zicclsm, porque sem os dois um acesso desalinhado não teria trap nem execução em hardware, e a elaboração falha. A base é o RV32I (`num_regs` 32) ou o RV32E (`num_regs` 16, ver [ISA/E/description.md](docs/pt-br/ISA/E/description.md)), e cada base aceita todas as 60 combinações de extensões, o que dá 120 perfis. A lista de perfis vem de `profiles/matrix.yaml`:

```bash
riscv-tools profiles --spec profiles/matrix.yaml                    # um nome por linha
riscv-tools profiles --spec profiles/matrix.yaml --format generics  # nome e flags -g do GHDL
make profile-matrix                                                        # elabora cada perfil com seus generics
```

Quando uma extensão está desabilitada pelo seu generic, as instruções correspondentes comportam-se como `NOP` (sem escrita em registrador, sem acesso à memória e sem parada do pipeline).

## 4. Verificação e Execução

### 4.1. Execução local

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Core.git
cd Core
uv sync

make check          # Verificação de sintaxe VHDL de todos os fontes em ordem topológica
make profiles       # Compilação e elaboração independente de cada perfil em profiles/*.yaml
make test           # Execução da suíte completa de testes cocotb (ou make test TEST=ALU para um alvo)
make paths          # Validação de existência de todos os caminhos listados nos manifestos
make formal         # Execução das provas formais (SymbiYosys) com o engine de FORMAL_ENGINE (bitwuzla por padrão)
```

### 4.2. Execução via Docker

A imagem `ghcr.io/insper-riscv/ci-vhdl:latest` publicada pelo repositório [insper-riscv/Infra](https://github.com/insper-riscv/Infra) já traz o GHDL (backend LLVM), Yosys, SymbiYosys, os solvers Yices, Bitwuzla e Boolector, `uv`, Python 3.14 e cocotb 2.1.0 pré-instalados:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/insper-riscv/ci-vhdl:latest \
  bash -c "uv sync && make check && make profiles && make test && make formal"
```

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](LICENSE).
