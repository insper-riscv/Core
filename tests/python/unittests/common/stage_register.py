"""Verificação comum dos registradores de estágio do pipeline.

Os registradores IF/ID, ID/EX, EX/MEM e MEM/WB têm o mesmo contrato:
capturam as entradas na borda de subida quando habilitados, mantêm o
estado em stall e se limpam com flush ou reset (que têm prioridade).
Cada teste de entidade declara os campos do seu registrador e, se
houver, as saídas derivadas, e chama check_stage_register.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng, check_equal


def no_derived(_values):
    """Registrador sem saídas derivadas."""
    return {}


class StageRegister:
    """Modelo e acesso ao registrador de estágio sob teste.

    Os campos são pares i_<nome> e o_<nome> de mesma largura. As saídas
    derivadas (sem entrada homônima) vêm de uma função das entradas.
    """

    def __init__(self, dut, fields, derived=None):
        """Guarda o DUT, os campos e as saídas derivadas."""
        self.dut = dut
        self.fields = fields
        self.derived = derived or no_derived
        self.prng = Prng(0x5EED)

    def zeros(self):
        """Devolve as entradas todas em zero."""
        return dict.fromkeys(self.fields, 0)

    def random_inputs(self):
        """Devolve um vetor aleatório (reprodutível) para os campos."""
        return {
            name: self.prng.getrandbits(width)
            for name, width in self.fields.items()
        }

    async def step(self, values, controls):
        """Aplica entradas e controles e avança uma borda de clock.

        Os controles vêm como (en, flush, rst).
        """
        enable, flush, reset = controls
        self.dut.i_en.value = enable
        self.dut.i_flush.value = flush
        self.dut.i_rst.value = reset
        for name, value in values.items():
            getattr(self.dut, f"i_{name}").value = value
        await RisingEdge(self.dut.i_clk)
        await Timer(1, unit="ns")

    def expect(self, values, message):
        """Confere todas as saídas contra as entradas capturadas."""
        expected = {**values, **self.derived(values)}
        for name, want in expected.items():
            got = int(getattr(self.dut, f"o_{name}").value)
            check_equal(got, want, f"{message}: o_{name}")

    def expect_clear(self, message):
        """Confere que todas as saídas estão em zero."""
        names = set(self.fields) | set(self.derived(self.zeros()))
        for name in names:
            got = int(getattr(self.dut, f"o_{name}").value)
            check_equal(got, 0, f"{message}: o_{name}")


async def start(reg):
    """Liga o clock e aplica reset por dois ciclos."""
    cocotb.start_soon(Clock(reg.dut.i_clk, 10, unit="ns").start())
    for _ in range(2):
        await reg.step(reg.zeros(), (0, 0, 1))
    reg.expect_clear("depois do reset")


async def check_capture(reg):
    """Com i_en alto, cada borda captura o vetor aplicado."""
    values = reg.zeros()
    for index in range(32):
        values = reg.random_inputs()
        await reg.step(values, (1, 0, 0))
        reg.expect(values, f"captura {index}")
    return values


async def check_hold(reg, held):
    """Com i_en baixo, o registrador mantém o último vetor capturado."""
    for index in range(4):
        await reg.step(reg.random_inputs(), (0, 0, 0))
        reg.expect(held, f"stall {index}")


async def check_clears(reg):
    """Flush e reset limpam, com prioridade sobre captura e stall."""
    for controls in ((1, 1, 0), (0, 1, 0), (1, 0, 1), (0, 0, 1)):
        await reg.step(reg.random_inputs(), (1, 0, 0))
        await reg.step(reg.random_inputs(), controls)
        reg.expect_clear(f"limpeza {controls}")


async def check_stage_register(reg):
    """Executa o contrato completo do registrador de estágio."""
    await start(reg)
    held = await check_capture(reg)
    await check_hold(reg, held)
    await check_clears(reg)
    values = reg.random_inputs()
    await reg.step(values, (1, 0, 0))
    reg.expect(values, "captura depois da limpeza")
