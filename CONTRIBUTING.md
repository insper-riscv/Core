# Guia de Contribuição

🌐 [Português](CONTRIBUTING.md) · [English](CONTRIBUTING.en.md)

Este documento define as regras obrigatórias de codificação VHDL, organização estrutural, documentação e verificação para qualquer contribuição ao repositório `Core`.

## 1. Normas VHDL e Compatibilidade de Síntese

Todo código de hardware do projeto é escrito e validado sob a norma **IEEE 1076-2008 (VHDL-2008)**, compilado no GHDL com a flag `--std=08` e sintetizado no Quartus Prime.

| Regra | Especificação |
| :--- | :--- |
| Norma da linguagem | VHDL-2008 (`--std=08`) em todos os arquivos `.vhd` |
| Pacotes IEEE permitidos | Apenas `ieee.std_logic_1164.all` e `ieee.numeric_std.all` |
| Pacotes proibidos | `std_logic_arith`, `std_logic_unsigned` e `std_logic_signed` nunca devem ser utilizados |
| Instanciação de módulos | Usar instanciação direta de entidade (`u_nome : entity work.nome_da_entidade`), sem declarações `component` redundantes |
| Mapeamento de portas (`port map`) | Associar sempre por nome (`i_porta => sinal`) e utilizar sinais intermediários para expressões lógicas ou fatias dinâmicas, pois o GHDL exige expressões globalmente estáticas nos formais/atuais de porta |
| Inferência de latches | Todo sinal atribuído em processo combinacional ou atribuição condicional deve receber valor padrão explícito em todos os ramos (`else` / `when others =>`) |

A norma de referência é a [IEEE Std 1076-2008, IEEE Standard VHDL Language Reference Manual](https://standards.ieee.org/ieee/1076/3666/). Em trabalhos acadêmicos, cite-a com a entrada BibTeX abaixo:

```bibtex
@misc{ieee1076,
  title        = {IEEE Standard VHDL Language Reference Manual},
  author       = {{IEEE}},
  year         = {2008},
  note         = {IEEE Std 1076-2008},
  howpublished = {\url{https://standards.ieee.org/ieee/1076/3666/}}
}
```

A organização em blocos reutilizáveis com interfaces e parâmetros explícitos (extensões em pastas próprias, controladas por generics) segue a [IEEE Std 1685, IEEE Standard for IP-XACT](https://standards.ieee.org/ieee/1685/10583/), cuja entrada BibTeX é:

```bibtex
@misc{ieee1685,
  title        = {IEEE Standard for IP-XACT, Standard Structure for Packaging, Integrating, and Reusing IP within Tool Flows},
  author       = {{IEEE}},
  year         = {2022},
  note         = {IEEE Std 1685-2022},
  howpublished = {\url{https://standards.ieee.org/ieee/1685/10583/}}
}
```

A metodologia de projeto para reuso de blocos de hardware segue o livro *Reuse Methodology Manual for System-on-a-Chip Designs* (3ª edição, Springer, 2002), de Keating e Bricaud, obra com direitos autorais cujo acesso depende de compra ou de biblioteca institucional:

```bibtex
@book{keating2002rmm,
  title     = {Reuse Methodology Manual for System-on-a-Chip Designs},
  author    = {Keating, Michael and Bricaud, Pierre},
  edition   = {3},
  year      = {2002},
  publisher = {Springer},
  isbn      = {978-1402071416}
}
```

## 2. Nomenclatura e Prefixos Obrigatórios em VHDL

Todos os identificadores de código devem ser escritos em **inglês**, enquanto todos os comentários e cabeçalhos devem ser escritos em **português**.

| Elemento VHDL | Convenção | Exemplos |
| :--- | :--- | :--- |
| Entidades, arquiteturas e pacotes | `snake_case` (exceto o topo estrutural `cpu`) | `stage_ex`, `control_unit`, `alu_consts`, `rtl` |
| Portas de entrada (`in`) | Prefixo obrigatório `i_` + `snake_case` | `i_clk`, `i_rst`, `i_rs1_val`, `i_pipe_run` |
| Portas de saída (`out`) | Prefixo obrigatório `o_` + `snake_case` | `o_alu_out`, `o_we_reg`, `o_stall`, `o_wb_data` |
| Generics | `snake_case` descritivo | `data_width`, `addr_width`, `has_m`, `has_zicsr` |
| Constantes (`constant`) | `UPPER_SNAKE_CASE` | `WORD_WIDTH`, `ALU_ADD`, `OPCODE_JALR`, `REG_ZERO` |
| Tipos e subtipos (`type`, `subtype`) | `snake_case` com sufixo `_t` | `word_t`, `reg_idx_t`, `alu_op_t`, `ctrl_bus_t` |
| Sinais e variáveis internas | `snake_case` (prefixado pelo estágio quando aplicável) | `ex_alu_result`, `id_imm`, `wb_ram_raw` |
| Rótulos de instância | Prefixo `u_` + `snake_case` | `u_alu`, `u_reg_file`, `u_pc_reg` |

## 3. Cabeçalhos (Headers) e Docstrings em VHDL

### 3.1. Cabeçalho Obrigatório de Arquivo

Todo arquivo `.vhd` deve iniciar com um bloco de cabeçalho de 72 colunas (`-- ====...====`) em português descrevendo a responsabilidade arquitetural do pacote ou da entidade:

```vhdl
-- ============================================================================
-- <Título curto do pacote ou entidade>
-- ============================================================================
-- <Descrição clara em português da função do módulo no processador,
--  interfaces principais, invariantes de ciclo/latência ou parâmetros.>
-- ============================================================================
```

Seções internas de uma arquitetura devem utilizar separadores de 72 colunas com hífens simples (`-- ----...----`).

### 3.2. Docstring Individual Acima de Cada Declaração

Cada declaração individual de `generic`, `port`, `constant`, `subtype`, `type`, `signal`, `alias` e `variable` deve possuir seu próprio comentário descritivo em português imediatamente na linha acima. Comentários na mesma linha (inline ao final da linha) não substituem a docstring acima da declaração:

```vhdl
entity mux_2x1 is
    generic(
        -- Largura em bits dos barramentos de entrada e saída
        data_width : natural := 32
    );
    port(
        -- Entrada selecionada quando i_sel vale '0'
        i_d0  : in  std_logic_vector(data_width - 1 downto 0);
        -- Entrada selecionada quando i_sel vale '1'
        i_d1  : in  std_logic_vector(data_width - 1 downto 0);
        -- Bit seletor entre i_d0 ('0') e i_d1 ('1')
        i_sel : in  std_logic;
        -- Saída multiplexada resultante
        o_out : out std_logic_vector(data_width - 1 downto 0)
    );
end entity mux_2x1;
```

## 4. Projeto para Reuso e Proibição de Duplicação

O projeto segue a prática de *Design for Reuse* descrita no *Reuse Methodology Manual* (Keating e Bricaud), que não é uma norma IEEE e não equivale ao SOLID da programação orientada a objetos. Cada regra abaixo se traduz em um critério verificável em revisão:

| # | Regra | Critério de revisão no `Core` |
| :--- | :--- | :--- |
| 1 | **Blocos de propósito único:** separar controle, caminho de dados e interface de protocolo em entidades distintas | Uma entidade com mais de uma função (por exemplo, decodificar e executar) deve ser dividida; o topo `core/cpu.vhd` apenas conecta os cinco estágios (`stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb`) e os quatro registradores de barreira (`reg_if_id`, `reg_id_ex`, `reg_ex_mem`, `reg_mem_wb`) |
| 2 | **Parametrização por `generic` e constantes de pacote:** nenhuma largura, profundidade ou recurso fixado dentro da arquitetura | Nenhum literal mágico (`"0110011"`, `x"300"`) na lógica dos estágios; todo código de opcode, operação da ULA, seletor de imediato, seletor de write-back e endereço de CSR reside no pacote de constantes de `common/` ou da pasta da extensão |
| 3 | **Interfaces padronizadas e intercambiáveis:** entidades com a mesma assinatura de portas podem ser trocadas sem alterar quem as instancia | Trocar a arquitetura de um bloco não pode mudar suas portas nem seu comportamento observável de fora |
| 4 | **Portas enxutas:** a entidade expõe somente as portas e os generics que usa | Sinais ou generics "para uso futuro" não entram em uma entidade |
| 5 | **Dependência apenas das portas:** o nível superior conhece a declaração da entidade, nunca detalhes internos de sua arquitetura | O topo nunca carrega lógica fina de implementação |
| 6 | **Composição com primitivos de `common/`:** reaproveitar os blocos-folha já verificados | Registradores simples instanciam `entity work.generic_register`, somadores dedicados instanciam `entity work.adder` e seletores estruturais usam `mux_2x1`, `mux_4x1`, `mux_tree` e `onehot_decoder`; não reimplementar com processos ou operadores redundantes o que o primitivo ou um sinal já calculado no estágio fornece |
| 7 | **Extensões como blocos opcionais:** cada extensão reside em diretório próprio, habilitada por generic booleano no topo `cpu`, e se comporta como `NOP` quando desabilitada | Contrato em [docs/pt-br/contracts/01-contrato-de-extensao.md](docs/pt-br/contracts/01-contrato-de-extensao.md) |

## 5. Regras de Documentação Markdown

Toda documentação do repositório mantém versões espelhadas em português (`README.md`, `docs/pt-br/`) e em inglês (`README.en.md`, `docs/en/`), obedecendo às seguintes regras:

1. **Seletor de idioma e rodapé de licença:** todo `README.md` e `README.en.md` traz no topo o seletor `🌐 [Português](...) · [English](...)`, e todo arquivo `.md` encerra com o rodapé de copyright e link para `LICENSE`.
2. **Seções numeradas e progressivas:** todas as seções a partir de `##` devem ser numeradas (`## 1.`, `### 1.1.`, `## 2.`) em ordem lógica de leitura.
3. **Pontuação direta:**
   - **Proibido o uso de travessão** em prosa ou tabelas; utilize vírgula, parênteses, ponto e vírgula ou dois-pontos conforme a relação sintática real.
   - **Proibidos dois-pontos encadeados** (mais de um `:` na mesma frase ou célula de tabela).
4. **Explicação de comportamento:** nunca cite o nome de um arquivo, módulo ou sinal interno como se o próprio nome explicasse o que o hardware faz; descreva sempre a operação realizada.
5. **Tabelas e LaTeX sem redundância:** dados estruturados devem estar em tabelas Markdown e expressões matemáticas/lógicas em blocos LaTeX (`$$ ... $$` ou `$ ... $`), sem repetir em prosa o que a tabela ou equação já enuncia.
6. **Sem histórico ou pendências na documentação técnica:** documentos de arquitetura e contratos descrevem exclusivamente o estado atual do hardware, sem changelogs internos nem listas de tarefas futuras.

## 6. Verificação Obrigatória Antes de Abrir Pull Request

Qualquer alteração em código VHDL, manifestos de perfil ou documentação deve passar sem erros pelos cinco comandos abaixo antes do envio:

```bash
make check          # Verifica a sintaxe VHDL-2008 de todos os arquivos em ordem topológica
make profiles       # Compila e elabora cada perfil em profiles/*.yaml no GHDL
make paths          # Confere que todos os caminhos referenciados em paths.yaml existem
make test           # Executa a suíte completa de testes unitários e de integração (cocotb + GHDL)
bash formal/run.sh  # Executa as provas formais (SymbiYosys + Z3) de csr_file e trap_unit
```

Ao adicionar, renomear ou remover qualquer arquivo `.vhd` ou `.md`, atualize imediatamente:
- `profiles/*.yaml`
- `tests/python/tests.json`
- `paths.yaml`
- `docs/pt-br/` e `docs/en/`

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](LICENSE).
