# Core

🌐 [Português](README.md) · [English](README.en.md)

Núcleo do processador RISC-V RV32 em VHDL-2008 organizado com uma pipeline de 5 estágios (IF, ID, EX, MEM e WB), modularizado por extensão da ISA (`I`, `M`, `Zicsr` e `Zifencei`) sob a entidade de topo (`core`), acompanhado de testes unitários por entidade via cocotb/GHDL e de verificação formal via SymbiYosys.

## 1. Documentação

- [AUTHORS.md](AUTHORS.md): autores com commits no repositório, com nome e conta do GitHub.
- [CONTRIBUTING.md](CONTRIBUTING.md): regras obrigatórias de contribuição, norma VHDL-2008 (`--std=08`), convenção de nomenclatura, prefixos `i_`/`o_`, cabeçalhos, docstrings e regras de documentação.
- [README.md](docs/pt-br/README.md): formatos das instruções de 32 bits do RISC-V, tabela de geração de imediatos e progressão incremental do caminho de dados para as 37 instruções da base RV32I.
- [ARCHITECTURE.md](docs/pt-br/ARCHITECTURE.md): microarquitetura do pipeline de 5 estágios, responsabilidades por estágio, caminhos de forwarding, detecção de hazard load-use, stall, flush e suporte às extensões `M`, `Zicsr` e `Zifencei`.
- [PIPELINE_ARCHITECTURE_GUIDE.md](docs/pt-br/PIPELINE_ARCHITECTURE_GUIDE.md): referência detalhada dos sinais de interconexão entre os estágios, barreiras síncronas (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`), equações de stall e flush e resolução de desvios.
- [DECODER.md](docs/pt-br/DECODER.md): especificação da palavra de controle de 21 bits da base RV32I, decodificação dedicada de `RV32M`, `Zicsr` e `Zifencei`, seleção de escrita no banco de registradores e detecção de instrução ilegal.
- [contracts/01-contrato-de-extensao.md](docs/pt-br/contracts/01-contrato-de-extensao.md): contrato de diretórios por extensão, manifestos de perfil (`profiles/*.yaml`) e ponto único de integração de novas extensões na entidade de topo.
- [contracts/02-barramento-e-memoria.md](docs/pt-br/contracts/02-barramento-e-memoria.md): protocolo de barramento de instruções e de dados (endereçamento em byte, habilitação por byte, handshake de espera por memória lenta e cache de instruções).
- [bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md](docs/pt-br/bugs/DIVISOR_SEM_SINAL_ACIMA_DE_2_31.md): análise matemática da faixa do resto parcial na divisão não-restauradora e do uso de 34 bits internos para divisores sem sinal acima de $2^{31}$.
- [bugs/FLUSH_COM_PIPELINE_PARADO.md](docs/pt-br/bugs/FLUSH_COM_PIPELINE_PARADO.md): análise da interação entre redirecionamento de desvio em EX e parada global do pipeline por espera de memória em MEM.
- [bugs/LOAD_EM_WB_DURANTE_STALL.md](docs/pt-br/bugs/LOAD_EM_WB_DURANTE_STALL.md): análise do load segurado em WB que era sobrescrito pelo load seguinte enquanto a unidade M para o pipeline.

## 2. Estrutura do Repositório

| Caminho | Conteúdo |
| :--- | :--- |
| `common/` | Blocos compartilhados por todos os perfis, incluindo pacotes de tipos e constantes, registradores de barreira entre estágios, unidade de controle base, banco de registradores, unidades de forwarding e hazard, gerador de PC e primitivos parametrizáveis |
| `I/` | Extensão inteira base RV32I, composta pela ULA, extensor de imediatos, extensor de leitura de memória e gerenciador de alinhamento de stores |
| `M/` | Extensão de multiplicação e divisão inteira RV32M, contendo decodificador dedicado, multiplicador sequencial de Booth radix-2, divisor não-restaurador de 34 bits e unidade integradora |
| `Zicsr/` | Extensão de registradores de controle e estado (CSRs) do modo máquina e unidade de detecção de exceções síncronas e retorno de trap (`MRET`) |
| `Zifencei/` | Extensão de sincronização da memória de instruções (`FENCE.I`), com suporte opcional a handshake de flush de cache de dados write-back |
| `core/` | Entidades dos 5 estágios do pipeline (`stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb`) e topo estrutural do processador (`core`) |
| `profiles/` | Manifestos de fontes e generics de cada perfil suportado (`rv32i.yaml`, `rv32im.yaml`, `rv32im_zicsr.yaml`, `rv32im_zicsr_zifencei.yaml`) em ordem de dependência |
| `formal/` | Propriedades em SystemVerilog (`csr_file_props.sv`, `trap_unit_props.sv`), configurações `.sby` e script de verificação formal via GHDL + Yosys + SymbiYosys |
| `tests/python/` | Testes unitários por entidade e de integração do topo em cocotb/GHDL ([documentação](tests/python/README.md)) |
| `tests/FPGA/entities/` | Projeto Quartus para validação em placa do banco de registradores ([documentação](tests/FPGA/entities/bancoRegistradores/README.md)) |

## 3. Perfis da ISA

O topo estrutural `core` recebe quatro generics booleanos que habilitam ou desabilitam cada extensão em tempo de elaboração:

| Perfil (`profiles/`) | Extensões ativas | Generics configurados no topo `core` |
| :--- | :--- | :--- |
| `rv32i` | RV32I | `has_m: false, has_zicsr: false, has_zifencei: false, has_dcache_Wb: false` |
| `rv32im` | RV32I + M | `has_m: true, has_zicsr: false, has_zifencei: false, has_dcache_Wb: false` |
| `rv32im_zicsr` | RV32I + M + Zicsr | `has_m: true, has_zicsr: true, has_zifencei: false, has_dcache_Wb: false` |
| `rv32im_zicsr_zifencei` | RV32I + M + Zicsr + Zifencei | `has_m: true, has_zicsr: true, has_zifencei: true, has_dcache_Wb: false` |

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
bash formal/run.sh  # Execução das provas formais (SymbiYosys + Z3) para csr_file e trap_unit
```

### 4.2. Execução via Docker

A imagem `ghcr.io/insper-riscv/ci-vhdl:latest` publicada pelo repositório [insper-riscv/Infra](https://github.com/insper-riscv/Infra) já traz o GHDL (backend LLVM), Yosys, SymbiYosys, Z3, `uv`, Python 3.14 e cocotb 2.1.0 pré-instalados:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/insper-riscv/ci-vhdl:latest \
  bash -c "uv sync --extra sim && make check && make profiles && make test && bash formal/run.sh"
```

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](LICENSE).
