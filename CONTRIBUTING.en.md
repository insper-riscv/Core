# Contribution Guide

🌐 [Português](CONTRIBUTING.md) · [English](CONTRIBUTING.en.md)

This document defines the mandatory VHDL coding, structural organization, documentation, and verification rules for any contribution to the `Core` repository.

## 1. VHDL-2008 Standard and Synthesis Compatibility

All hardware code in the project is written and validated under the **IEEE 1076-2008 (VHDL-2008)** standard, compiled in GHDL with the `--std=08` flag, and synthesized in Quartus Prime.

| Rule | Specification |
| :--- | :--- |
| Language standard | VHDL-2008 (`--std=08`) across all `.vhd` files |
| Permitted IEEE packages | Only `ieee.std_logic_1164.all` and `ieee.numeric_std.all` |
| Prohibited packages | `std_logic_arith`, `std_logic_unsigned`, and `std_logic_signed` must never be used |
| Module instantiation | Use direct entity instantiation (`u_name : entity work.entity_name`), without redundant `component` declarations |
| Port mapping (`port map`) | Always associate by name (`i_port => signal`) and use intermediate signals for logical expressions or dynamic slices, because GHDL requires globally static expressions in port map actuals |
| Latch prevention | Every signal assigned in a combinational process or conditional assignment must receive an explicit default value across all branches (`else` / `when others =>`) |

The reference standard is [IEEE Std 1076-2008, IEEE Standard VHDL Language Reference Manual](https://standards.ieee.org/ieee/1076/3666/). In academic work, cite it with the BibTeX entry below:

```bibtex
@misc{ieee1076,
  title        = {IEEE Standard VHDL Language Reference Manual},
  author       = {{IEEE}},
  year         = {2008},
  note         = {IEEE Std 1076-2008},
  howpublished = {\url{https://standards.ieee.org/ieee/1076/3666/}}
}
```

The organization into reusable blocks with explicit interfaces and parameters (extensions in their own folders, controlled by generics) follows [IEEE Std 1685, IEEE Standard for IP-XACT](https://standards.ieee.org/ieee/1685/10583/), whose BibTeX entry is:

```bibtex
@misc{ieee1685,
  title        = {IEEE Standard for IP-XACT, Standard Structure for Packaging, Integrating, and Reusing IP within Tool Flows},
  author       = {{IEEE}},
  year         = {2022},
  note         = {IEEE Std 1685-2022},
  howpublished = {\url{https://standards.ieee.org/ieee/1685/10583/}}
}
```

The design-for-reuse methodology for hardware blocks follows the book *Reuse Methodology Manual for System-on-a-Chip Designs* (3rd edition, Springer, 2002) by Keating and Bricaud, a copyrighted work available only by purchase or through an institutional library:

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

## 2. Mandatory VHDL Naming and Port Prefixes

All code identifiers must be written in **English**, whereas all comments and file headers must be written in **Portuguese**.

| VHDL Element | Convention | Examples |
| :--- | :--- | :--- |
| Entities, architectures, and packages | `snake_case` (except the structural top level `core`) | `stage_ex`, `control_unit`, `alu_consts`, `rtl` |
| Input ports (`in`) | Mandatory `i_` prefix + `snake_case` | `i_clk`, `i_rst`, `i_rs1_val`, `i_pipe_run` |
| Output ports (`out`) | Mandatory `o_` prefix + `snake_case` | `o_alu_out`, `o_we_reg`, `o_stall`, `o_wb_data` |
| Generics | Descriptive `snake_case` | `data_width`, `addr_width`, `has_m`, `has_zicsr` |
| Constants (`constant`) | `UPPER_SNAKE_CASE` | `WORD_WIDTH`, `ALU_ADD`, `OPCODE_JALR`, `REG_ZERO` |
| Types and subtypes (`type`, `subtype`) | `snake_case` with `_t` suffix | `word_t`, `reg_idx_t`, `alu_op_t`, `ctrl_bus_t` |
| Internal signals and variables | `snake_case` (prefixed by the stage name where applicable) | `ex_alu_result`, `id_imm`, `wb_ram_raw` |
| Instance labels | `u_` prefix + `snake_case` | `u_alu`, `u_reg_file`, `u_pc_reg` |

## 3. VHDL File Headers and Docstrings

### 3.1. Mandatory File Header

Every `.vhd` file must begin with a 72-column header block (`-- ====...====`) in Portuguese describing the architectural responsibility of the package or entity:

```vhdl
-- ============================================================================
-- <Short title of the package or entity>
-- ============================================================================
-- <Clear description in Portuguese of the module's role in the processor,
--  primary interfaces, cycle/latency invariants, or parameters.>
-- ============================================================================
```

Internal sections within an architecture must use 72-column single-hyphen dividers (`-- ----...----`).

### 3.2. Individual Docstring Above Every Declaration

Every individual `generic`, `port`, `constant`, `subtype`, `type`, `signal`, `alias`, and `variable` declaration must have its own descriptive comment in Portuguese on the line immediately above it. End-of-line inline comments do not replace the docstring above the declaration:

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

## 4. Design for Reuse and Zero Duplication

The project follows the *Design for Reuse* practice described in the *Reuse Methodology Manual* (Keating and Bricaud). Each rule below translates into a criterion that can be checked in review:

| # | Rule | Review criterion in `Core` |
| :--- | :--- | :--- |
| 1 | **Single-purpose blocks:** separate control, datapath, and protocol interface into distinct entities | An entity with more than one job (for example, decoding and executing) must be split; the top level `core/core.vhd` only connects the five stages (`stage_if`, `stage_id`, `stage_ex`, `stage_mem`, `stage_wb`) and the four barrier registers (`reg_if_id`, `reg_id_ex`, `reg_ex_mem`, `reg_mem_wb`) |
| 2 | **Parameterization through `generic` and package constants:** no width, depth, or feature fixed inside the architecture | No magic literal (`"0110011"`, `x"300"`) in stage logic; every opcode, ALU operation, immediate selector, write-back selector, and CSR address lives in the constant package under `common/` or the extension folder |
| 3 | **Standardized, interchangeable interfaces:** entities with the same port signature can be swapped without changing whoever instantiates them | Changing a block's architecture must not change its ports or its externally observable behavior |
| 4 | **Lean ports:** the entity exposes only the ports and generics it uses | Signals or generics "for future use" do not belong in an entity |
| 5 | **Dependence on ports only:** the upper level knows the entity declaration, never the internals of its architecture | The top level never carries fine-grained implementation logic |
| 6 | **Composition with `common/` primitives:** reuse the already verified leaf blocks | Simple registers instantiate `entity work.generic_register`, dedicated adders instantiate `entity work.adder`, and structural selectors use `mux_2x1`, `mux_4x1`, `mux_tree`, and `onehot_decoder`; do not reimplement with ad-hoc processes or operators what the primitive or an already computed stage signal provides |
| 7 | **Extensions as optional blocks:** each extension lives in its own directory, enabled by a boolean generic on the `core` top level, and behaves as `NOP` when disabled | Contract in [docs/en/contracts/01-contrato-de-extensao.md](docs/en/contracts/01-contrato-de-extensao.md) |

## 5. Python Standards

The Python code (runner and tests under `tests/python/`) follows [PEP 8](https://peps.python.org/pep-0008) (style) and [PEP 257](https://peps.python.org/pep-0257) (docstrings); `ruff` checks both (rules `E`, `W`, `N`, and `D`).

### 5.1. Code Style (PEP 8)

> **Deviation from PEP 8.** PEP 8 asks for comments in English, and this project writes them in **Portuguese**. Every other PEP 8 recommendation on comments still applies, namely complete sentences, kept up to date, and never restating what the code already says. Identifiers stay in English.

| Rule | Specification |
| :--- | :--- |
| Indentation | 4 spaces per level; tabs prohibited |
| Encoding | UTF-8, with no encoding declaration in the file |
| Line length | At most 79 characters for code; 72 for docstrings and comments |
| Naming | `snake_case` for functions, methods, variables, and modules; `PascalCase` for classes; `UPPER_SNAKE_CASE` for constants; `_` prefix for internal names |
| Imports | At the top of the file, one per line, in three groups separated by a blank line (standard library, third party, project), each group sorted alphabetically; absolute imports only (relative imports prohibited); `import *` prohibited |
| Blank lines | Two between module-level definitions; one between methods |
| Whitespace | One space around operators and after commas; none before a call's `(`, inside brackets, or at the end of a line |
| Comparisons | `is` and `is not` for `None`; `if seq:` instead of `if len(seq):`; never `== True` or `== False` |
| Exceptions | `except` always names the specific exception; bare `except:` prohibited |
| Comments | **In Portuguese** (deviation from PEP 8); complete sentences, capitalized, on their own line or after two spaces at the end of code, starting with `# `; they explain why, not what the code does |
| Language | Identifiers in **English**; comments in **Portuguese** |

### 5.2. Docstrings (PEP 257)

| Rule | Specification |
| :--- | :--- |
| Scope | Every public module, class, function, and method has a docstring |
| Delimiter | Triple double quotes (`"""`), including one-line docstrings |
| Summary | First line on the same line as the opening quotes, in the imperative mood, ending with a period |
| One-line docstring | Closing quotes on the same line, no blank line before or after the text |
| Multi-line docstring | Summary, blank line, detailed description; closing quotes alone on the last line |
| Classes | Docstring on the class, not on `__init__`; blank line after the docstring |
| Sections | NumPy style (`Parameters`, `Returns`, `Raises`, `Examples`), with the type repeating the annotation |
| Language | Portuguese |

```python
def fetch_user(user_id: str, include_roles: bool = False) -> User:
    """Busca um usuário pelo identificador.

    Parameters
    ----------
    user_id : str
        Identificador único do usuário.
    include_roles : bool, optional
        Inclui a lista de papéis na resposta, por padrão False.

    Returns
    -------
    User
        Dados do usuário.
    """
```

### 5.3. Tooling and Process

| Rule | Specification |
| :--- | :--- |
| Package manager | `uv` (`uv add`, `uv sync`, `uv run`); `pip`, `pip install`, and `python -m pip` are prohibited |
| Tests | `pytest`; every new behavior comes with a test |
| Typing | Complete annotations, checked by Pyright and Pyrefly, both in `strict` mode |
| Style and quality | `ruff` for lint and formatting; `pylint` with a minimum score of 10; `deptry` for declared and used dependencies |
| Complexity and duplication | `complexipy` with a maximum of 10 per function; `codeclone` for duplicated code |
| Security | `semgrep` for static analysis; `uv audit` for dependency vulnerabilities |

## 6. Markdown Documentation Rules

All repository documentation maintains mirrored versions in Portuguese (`README.md`, `docs/pt-br/`) and English (`README.en.md`, `docs/en/`), following these rules:

1. **Language switcher and license footer:** every `README.md` and `README.en.md` includes the `🌐 [Português](...) · [English](...)` switcher at the top, and every `.md` file ends with the copyright footer linking to `LICENSE`.
2. **Numbered progressive sections:** all sections starting at `##` must be numbered (`## 1.`, `### 1.1.`, `## 2.`) in a logical reading order.
3. **Direct punctuation:**
   - **Em-dashes are prohibited** in prose and tables; use commas, parentheses, semicolons, or colons according to the actual syntactic relationship.
   - **Chained colons are prohibited** (more than one `:` in the same sentence or table cell).
4. **Behavior explanation:** never cite an internal file, module, or signal name as if the name itself explained what the hardware does; always describe the operation performed.
5. **Non-redundant tables and LaTeX:** structured data belongs in Markdown tables and mathematical/boolean equations in LaTeX blocks (`$$ ... $$` or `$ ... $`), without repeating in prose what the table or equation already states.
6. **No changelog or open TODOs in technical docs:** architecture and contract documents describe exclusively the current state of the hardware, without historical bugfix notes or unimplemented work lists.
7. **Usage guides only instruct:** installation and run instructions say how to do it, without justifying the choice of method.

## 7. Mandatory Verification Before Opening a Pull Request

Any change to VHDL code, profile manifests, or documentation must pass all five commands below without errors before submission:

```bash
make check          # Check VHDL-2008 syntax of all files in topological order
make profiles       # Compile and elaborate every profile in profiles/*.yaml under GHDL
make paths          # Verify that all paths referenced in paths.yaml exist
make test           # Run the full unit and integration test suite (cocotb + GHDL)
bash formal/run.sh  # Run the formal proofs (SymbiYosys + Z3) for csr_file and trap_unit
```

The `python-static-analysis` CI job runs `ruff`, `pycodestyle`, `pydocstyle`, `pylint`, `pyright`, `pyrefly`, `deptry`, `complexipy`, `codeclone`, `semgrep` and `uv audit` over the Python files, and the job name is the check the default-branch ruleset requires, so do not rename it.

When adding, renaming, or removing any `.vhd` or `.md` file, immediately update:
- `profiles/*.yaml`
- `tests/python/tests.json`
- `paths.yaml`
- `docs/pt-br/` and `docs/en/`

The CI runs these checks on every push. On a pull request from someone outside the project, it starts only after a member who can merge approves the run in the pull request page.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](LICENSE).
