"""Testes de runner."""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

# cocotb 2.0 split the Python test-runner API out of the main cocotb
# package into cocotb-tools, imported as cocotb_tools.runner — this
# repo's requirements.txt pulls unpinned cocotb, which now resolves to
# 2.x, so the old `cocotb.runner` import 404s. See insper-riscv/Tools'
# own sim_runner module for the same migration.
from cocotb_tools.check_results import get_results
from cocotb_tools.runner import get_runner


def _build_dir(tests_root, test_module, toplevel):
    """Return the build directory of a test, created if missing."""
    if ".entities." in test_module:
        group = "entities"
    elif ".instructions." in test_module:
        group = "instructions"
    else:
        group = "misc"
    name = test_module.rsplit(".", maxsplit=1)[-1]
    leaf = name if group == "instructions" else toplevel
    build_dir = tests_root / "python/sim_build" / group / leaf
    build_dir.mkdir(parents=True, exist_ok=True)
    return build_dir


def _resolve_parameter(value, repo_root):
    """Turn one generic of tests.json into the text the simulator takes.

    A text that names an existing file becomes its absolute path, first
    looking in the current directory and then in the repository root.
    Anything else is kept as it came, for the flags that are no path.
    """
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    for candidate in (Path(value), repo_root / value):
        if candidate.exists():
            return str(candidate.resolve())
    return str(value)


def run_cocotb_test(
    toplevel: str,
    sources: list,
    test_module: str,
    parameters: dict | None = None,
    **simulator_args: list,
):
    """Build a toplevel and run a cocotb module on it.

    The simulator arguments come by name: build_args goes to the
    build and test_args to the run.
    """
    unknown = simulator_args.keys() - {"build_args", "test_args"}
    if unknown:
        raise TypeError(f"unknown simulator arguments: {sorted(unknown)}")
    tests_root = Path(__file__).resolve().parents[1]
    repo_root = Path(__file__).resolve().parents[2]
    sys.path.append(str(repo_root))

    runner = get_runner(os.getenv("SIM", "ghdl"))
    build_dir = _build_dir(tests_root, test_module, toplevel)
    resolved = {
        key: _resolve_parameter(value, repo_root)
        for key, value in (parameters or {}).items()
    }

    runner.build(
        vhdl_sources=[repo_root / src for src in sources],
        hdl_toplevel=toplevel,
        always=True,
        build_dir=build_dir,
        parameters=resolved,
        build_args=simulator_args.get("build_args") or [],
    )

    wave_file = build_dir / "waves.ghw"
    results_xml = runner.test(
        hdl_toplevel=toplevel,
        hdl_toplevel_lang="vhdl",
        test_module=test_module,
        build_dir=build_dir,
        plusargs=[f"--wave={wave_file}"],
        test_args=simulator_args.get("test_args") or [],
    )

    print(f"Waves: {wave_file} (gerado)")

    # runner.test() returns normally when a cocotb test fails; the
    # failures are only in results.xml
    total, failed = get_results(results_xml)
    if failed:
        raise RuntimeError(f"{failed} of {total} cocotb tests failed")


_OPT_OUT_KEYS = ("skip", "skip_reason")


def _load_configs(json_path):
    """Read tests.json, exiting with a message when it is unusable."""
    try:
        with json_path.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Erro: Arquivo de configuração '{json_path}' não encontrado.")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Erro: O arquivo JSON '{json_path}' está mal formatado.")
        sys.exit(1)


def _run_config(config):
    """Run one tests.json entry, without its opt-out keys."""
    run_cocotb_test(
        **{k: v for k, v in config.items() if k not in _OPT_OUT_KEYS}
    )


def _run_all(configs):
    """Run every entry of tests.json that is not opted out.

    "skip"/"skip_reason": a config-level opt-out (not a removal) for a
    test that's currently known-broken for a reason unrelated to
    whatever change is being tested right now -- same spirit as the
    asm/c suite's own .off files, adapted to this suite's single
    tests.json instead of one file per test. Only skipped in the "all"
    sweep; running it by name explicitly (`runner.py <name>`) still
    attempts it, e.g. to check whether a fix actually resolved it.
    """
    print("Executando TODOS os testes definidos em tests.json...")
    failures = []
    for name, config in configs.items():
        if config.get("skip"):
            reason = config.get("skip_reason", "no reason given")
            print(f"\n{'=' * 20} PULANDO TESTE: {name.upper()} {'=' * 20}")
            print(f"[SKIP] {reason}")
            continue
        print(f"\n{'=' * 20} INICIANDO TESTE: {name.upper()} {'=' * 20}")
        try:
            _run_config(config)
            print(
                f"{'-' * 20} TESTE {name.upper()} FINALIZADO COM SUCESSO "
                f"{'-' * 20}"
            )
        except (RuntimeError, OSError, subprocess.SubprocessError) as e:
            failures.append(name)
            print(f"[ERRO] O teste '{name}' falhou: {e}")
    print("\nTodos os testes foram executados.")
    if failures:
        print(
            f"[ERRO] {len(failures)} teste(s) falharam: {', '.join(failures)}"
        )
        sys.exit(1)


def _run_named(configs, test_name):
    """Run the entry called test_name, even if it is marked skip."""
    print(f"Executando teste específico: {test_name}")
    config = configs[test_name]
    if config.get("skip"):
        print(
            f"[AVISO] '{test_name}' está marcado como skip "
            f"({config.get('skip_reason', 'no reason given')}) -- "
            f"rodando mesmo assim, por ter sido pedido explicitamente."
        )
    _run_config(config)
    print(f"\nTeste {test_name} finalizado.")


def main():
    """Run the entity tests listed in tests.json."""
    tests_root = Path(__file__).resolve().parents[1]
    configs = _load_configs(tests_root / "python/tests.json")

    parser = argparse.ArgumentParser(
        description="Runner de Testes Cocotb para o projeto RV32I"
    )
    parser.add_argument(
        "test_name",
        nargs="?",
        default="all",
        help=(
            "Nome do teste a ser executado. Opções: "
            f"{[*list(configs.keys()), 'all']}"
        ),
    )
    args = parser.parse_args()

    if args.test_name == "all":
        _run_all(configs)
    elif args.test_name in configs:
        _run_named(configs, args.test_name)
    else:
        print(f"Erro: Teste '{args.test_name}' não encontrado em tests.json.")
        print(f"Opções disponíveis: {[*list(configs.keys()), 'all']}")
        sys.exit(1)


if __name__ == "__main__":
    main()
