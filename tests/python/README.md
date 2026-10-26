# `tests/python`: Testes Unitários por Entidade (Cocotb + GHDL)

🌐 [Português](README.md) · [English](README.en.md)

Suíte de testbenches em Python (cocotb) que exercita individualmente as entidades VHDL do processador (`alu`, `reg_file`, `control_unit`, `hazard_detection_unit`, `forwarding_unit`, `bubble_mux`, `extender_imm`, `extender_ram`, `store_manager`, `m_decode`, `non_restoring_divider_rv32`, `csr_decode`, `csr_file`, `trap_unit` e o topo `cpu`), conduzindo as portas diretamente a partir do simulador GHDL.

## 1. Estrutura de Diretórios

```
tests/python/
├── runner.py                    # Carregador do catálogo e executor cocotb/GHDL
├── tests.json                   # Catálogo de alvos: nome -> {toplevel, sources, test_module, parameters}
├── unittests/
│   ├── common/                  # Testes das entidades de common/ e tabela de referência (data/riscv_opcodes.csv)
│   ├── I/                       # Testes das entidades da extensão base I/
│   ├── M/                       # Testes do decodificador e divisor da extensão M/
│   ├── Zicsr/                   # Testes de csr_decode, csr_file e trap_unit
│   └── cores/                   # Testes de integração do topo cpu (stalls de SDRAM, I-cache e FENCE.I)
└── sim_build/                   # Artefatos gerados por simulação (<grupo>/<nome>/waves.ghw)
```

## 2. Execução

```bash
make test                # Executa todas as entradas ativas de tests.json
make test TEST=ALU       # Executa apenas uma entrada específica pelo nome no catálogo
```

A variável de ambiente `SIM` seleciona o simulador (padrão `ghdl`).

## 3. Catálogo de Testes (`tests.json`)

Cada chave de `tests/python/tests.json` define um alvo de teste com os seguintes campos:

| Campo | Significado |
| :--- | :--- |
| `toplevel` | Nome da entidade VHDL sob teste (por exemplo, `alu`, `reg_file`, `cpu`) |
| `sources` | Lista de arquivos VHDL necessários, relativos à raiz do repositório e em ordem de dependência de compilação |
| `test_module` | Módulo Python contendo os testes `@cocotb.test()` |
| `parameters` | Dicionário opcional de generics passados ao simulador na elaboração (por exemplo, `{"has_m": false, "has_zifencei": true}`) |
| `build_args` / `test_args` | Argumentos adicionais repassados ao GHDL (por exemplo, `["--std=08"]`) |
| `skip` | Booleano opcional; quando `true`, omite o alvo na execução completa sem filtro |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../LICENSE).
