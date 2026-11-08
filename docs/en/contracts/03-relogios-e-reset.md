# 3. Clocks and Reset (contract K7)

## 1. Scope

The SoC asks for clocks by role and never by PLL output. This contract defines the roles, where the value of each one comes from and when the reset ends. The generated top of the board connects a role to a PLL output, and no module of the SoC names a PLL, an FPGA family or a board. The bus and memory contracts ([02-barramento-e-memoria.md](02-barramento-e-memoria.md) and the memory contract of the Memory repository) hold inside each role.

## 2. Clock roles

| Role | Use | Origin of the value |
| :--- | :--- | :--- |
| `core` | Core and data memories | `platform.yaml`, `clocks.core` |
| `fetch` | Instruction memories | `platform.yaml`, `clocks.fetch`, with phase relative to `core` |
| `mem` | Device controller | `platform.yaml` or the limit of the chip, the lower of the two |
| `mem_pin` | Clock that leaves through the chip pin | Phase from the chip and the board |
| `rst` | SoC reset, active at `'1'` | Generated top |

A module gets one clock port for each role it uses, named with the role (for example `i_clk_core`), and the frequencies and phases reach it only through the top. The value of a role is the frequency asked of the PLL, so a module never assumes a number of megahertz.

## 3. Reset

The reset `rst` is `'1'` while the PLL has not locked and is released after the lock. The latency of the reset, as a function of the lock instant $t_{lock}$ and of the period $T_{core}$ of the `core` role, is

$$ t_{rst} = t_{lock} + 2\,T_{core} $$

The two `core` cycles after the lock give the reset time to reach every register before the first request of the core.

## 4. Crossing between roles

A signal that leaves one role and enters another crosses the domain by signal inversion and two synchronization flip-flops, as section 4 of the memory contract describes. The contract does not admit a control signal read in a domain that is not its own without this synchronization.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
