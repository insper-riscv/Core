# 2. Bus Interface and Memory Map

## 1. Processor Address Map

The limits of the instruction address space (IF stage) and of the data address space (MEM and WB stages) reach the stages as constants of the `config_pkg`, which `riscv-tools` generates from the `platform.yaml` of each platform. The core knows only three regions, the Boot memory, the FLASH and the RAM. The package `src/shared/mem_map_consts.vhd` holds the functions the stages use to decide the region of an address from these constants.

| `config_pkg` constant | Default | Region it delimits |
| :--- | :--- | :--- |
| `BOOT_MEMORY_BASE`, `BOOT_MEMORY_END` | `0`, `0x00001000` | The Boot memory occupies `[0, 2**BOOT_MEMORY_BITS)`, that is `0x00000000 .. 0x00000FFF` by default, and is always reached through the direct port |
| `FLASH_BASE`, `FLASH_END` | `0x00001000`, `0x00008000` | Range of the FLASH in bytes, with the exclusive end (`0x00001000 .. 0x00007FFF` by default); it must have a positive size and start after the Boot memory |
| `FLASH_ON_BUS` | `false` | False, the FLASH is reached through the direct port of the core, of fixed latency and with no handshake; true, through the bus (`o_ext_*` and the instruction port), on or off the chip |
| `RAM_BASE`, `RAM_END` | `0x00008000`, `0x40000000` | Range of the RAM in bytes, with the exclusive end (`0x00008000 .. 0x3FFFFFFF` by default); it starts after the FLASH |
| `RAM_ON_BUS` | `false` | False, the RAM is reached through the direct port (`o_ram_*`); true, through the bus (`o_ext_*`) |
| `HAS_ICACHE`, `HAS_DCACHE` | `false` | The instruction cache requires `FLASH_ON_BUS` and the data cache requires `RAM_ON_BUS`; `check_isa` refuses the other combinations |

The path of an access follows the region, not the role of the access:

| Region | Fetch, load or store |
| :--- | :--- |
| Boot memory | Direct port |
| FLASH | Direct port with `FLASH_ON_BUS` false, bus with it true |
| RAM | Direct port with `RAM_ON_BUS` false, bus with it true |
| Outside the three regions | Bus (external port); with no slave that takes the address, the external port answers an error |

The role of the access only chooses the cache, and only when the region is on the bus: the fetch goes through the instruction cache and the load and store through the data cache. Each region comes from comparing the address with constant limits, and the bases that are powers of 2 become bit tests in synthesis. The core no longer has a peripheral window or an external window: the interconnect, outside the core, decodes the peripherals.

The Boot memory and the FLASH are read-only, so a store to them raises the store access fault (cause 7, with `HAS_ACCESS_FAULTS`). An instruction fetch is valid only in the Boot memory, in the FLASH and, with `RAM_ON_BUS`, in the RAM (through the instruction cache); elsewhere, `HAS_ACCESS_FAULTS` raises the instruction access fault (cause 1). The hardware misaligned access serves the main memory, which is everything that is neither the Boot memory nor the direct FLASH, and does not cross the end of a region with a path of its own.

## 2. Instruction Fetch Interfaces (IF Stage)

The IF stage (`src/core/stage_if.vhd`) presents the current PC address on `o_if_addr` with `o_if_rden = '1'` and selects the instruction by the region of the address:

| `core` top-level port | Direction | Address region | Description |
| :--- | :--- | :--- | :--- |
| `o_if_addr` | `out` (`addr_t`) | All | Byte address of the current Program Counter |
| `o_if_rden` | `out` | All | Instruction read enable (fixed at `'1'`) |
| `i_boot_memory_data` | `in` | Boot memory | 32-bit instruction word returned by the Boot memory |
| `i_flash_data` | `in` | FLASH with `FLASH_ON_BUS` false | 32-bit instruction word returned by port 1 of the Flash memory |
| `o_ic_sel` | `out` | Bus | Indicates that the current PC points to the region served by the external instruction cache (the FLASH with `FLASH_ON_BUS`, the RAM with `RAM_ON_BUS` and whatever lies outside the three regions) |
| `i_ic_data` | `in` | Bus | 32-bit instruction word supplied by the external instruction cache |
| `i_ic_ready` | `in` | Bus | Signals that `i_ic_data` holds the valid instruction for `o_if_addr`; while it is `'0'` with `o_ic_sel = '1'`, the PC freezes and `reg_if_id` receives a bubble (`i_valid = '0'`) |
| `o_ic_inval` | `out` | Cache control | 1-cycle pulse generated on the completion of a `FENCE.I` instruction to invalidate the external instruction cache |

## 3. Data Memory Interfaces (MEM and WB Stages)

In the MEM stage (`src/core/stage_mem.vhd`), the effective address computed in the EX stage is routed to one of the three data interfaces. In the WB stage (`src/core/stage_wb.vhd`), the corresponding data read is selected and aligned by the `src/I-E/extender_ram.vhd` module.

### 3.1. Flash Memory Data Port (Boot memory and direct FLASH)

Used to read constants (`.rodata`) and to copy the `.data` section at start-up, with a fixed synchronous latency of 1 cycle. It serves the Boot memory and, with `FLASH_ON_BUS` false, the FLASH:

| `core` top-level port | Direction | Stage | Meaning |
| :--- | :--- | :--- | :--- |
| `o_flash_addr2` | `out` (`addr_t`) | MEM | Byte address of the Flash read |
| `o_flash_rden2` | `out` | MEM | Read enable (`exmem_re_ram and exmem_valid and is_flash_data`) |
| `i_flash_data2` | `in` | WB | 32-bit word returned in the next cycle |

### 3.2. Direct RAM (`[RAM_BASE, RAM_END)` with `RAM_ON_BUS` false)

Synchronous data memory with 1-cycle latency and writes controlled by a byte mask:

| `core` top-level port | Direction | Stage | Meaning |
| :--- | :--- | :--- | :--- |
| `o_ram_addr` | `out` (`addr_t`) | MEM | Byte address of the access |
| `o_ram_wdata` | `out` | MEM | 32-bit word with the write bytes positioned by the `store_manager` |
| `o_ram_byteena` | `out` | MEM | 4-bit mask telling which bytes of `o_ram_wdata` must be written |
| `o_ram_en` | `out` | MEM | General enable of the direct RAM |
| `o_ram_wren` | `out` | MEM | Write enable of the direct RAM |
| `o_ram_rden` | `out` | MEM | Read enable of the direct RAM |
| `i_ram_rdata` | `in` | WB | 32-bit word read from the direct RAM in the next cycle |

### 3.3. Variable-Latency External Port (Bus)

Every read or write that the two direct ports do not serve uses the external master port of the processor: the FLASH with `FLASH_ON_BUS`, the RAM with `RAM_ON_BUS` and every address outside the Boot memory, the FLASH and the RAM:

| `core` top-level port | Direction | Stage | Meaning |
| :--- | :--- | :--- | :--- |
| `o_ext_addr` | `out` (`addr_t`) | MEM | Byte address of the external access |
| `o_ext_wdata` | `out` | MEM | Aligned 32-bit write data |
| `o_ext_byteena` | `out` | MEM | Byte enable mask (4 bits) |
| `o_ext_rden` | `out` | MEM | Read request active while the valid access is in MEM |
| `o_ext_wren` | `out` | MEM | Write request active while the valid access is in MEM |
| `i_ext_rdata` | `in` | WB | 32-bit word returned by the external slave |
| `i_ext_ready` | `in` | MEM | Logic level that indicates completion of the external transaction (`'0'` holds the pipeline; default `'1'` when unconnected) |
| `i_ext_error` | `in` | MEM | Logic level raised together with `i_ext_ready` when no slave takes the address (default `'0'` when unconnected) |
| `o_mem_advance` | `out` | Global | Indicates to the external slave that the MEM stage advanced on the current clock edge (`base_run = '1'`) |

External handshake protocol rules:

1. **Stability during wait:** while `sdram_access = '1'` and `i_ext_ready = '0'`, the `o_ext_wait` signal keeps `base_run = '0'`, freezing `reg_ex_mem` and keeping `o_ext_addr`, `o_ext_wdata`, `o_ext_byteena`, `o_ext_rden` and `o_ext_wren` stable.
2. **Level acknowledge (`i_ext_ready`):** the external slave must hold `i_ext_ready = '1'` until it observes `o_mem_advance = '1'`, ensuring the completion is not lost if the `multdiv` unit is also holding the pipeline in the same cycle.
3. **Read data preservation (`i_ext_rdata`):** the `i_ext_rdata` word stays stable until the WB cycle in which the load instruction is consumed by `stage_wb`.
4. **Branch flush inhibition during wait:** branches and jumps taken in the EX stage only flush `reg_if_id` and `reg_id_ex` when `pipe_run = '1'`, keeping the branch instruction in EX until the MEM access finishes.
5. **Error answer (`i_ext_error`):** the slave raises `i_ext_error = '1'` in the same cycle as `i_ext_ready = '1'` when no slave takes the address, and the transaction has no effect on the slave. With `HAS_ACCESS_FAULTS`, the MEM stage raises in that cycle the load access fault (`mcause = 5`) or the store access fault (`mcause = 7`), with the effective address in `mtval` and the `mepc` of the instruction itself, through the same path as the address exception (`mem_trap_take`): the instruction in EX is discarded, the load writes no register and the `minstret` count does not include it. In a misaligned access that spans two words, the error of either word raises the fault of the access. Without `HAS_ACCESS_FAULTS`, the error is ignored.

Contract K1 is this external port. In it, the prefix of the ports is `ext` (`o_ext_*` and `i_ext_*`) and the behaviour is that of the rules above, the same for any region behind it: an emulated backend (FPGA internal memory) or a device backend (the chip on the board). The core sees only the handshake, never what realises the region.

## 4. Sub-Word Alignment and Misalignment Exceptions

The data bus always operates on 32-bit words accompanied by `byteena`:

- **Naturally aligned accesses (`LB`/`LBU`/`SB` at any address, `LH`/`LHU`/`SH` at even addresses, `LW`/`SW` at multiples of 4):** on a store, `src/I-E/store_manager.vhd` replicates the byte or halfword across the byte lanes selected by `ea[1:0]` and asserts the corresponding bits of `o_byte_mask`; on a load, `src/I-E/extender_ram.vhd` extracts the slice selected by `ea[1:0]` and applies sign or zero extension in the WB stage.
- **Misaligned accesses (`LW`/`SW` with `ea[1:0] /= "00"` or `LH`/`LHU`/`SH` with `ea[0] = '1'`):** with `HAS_ZICCLSM = true` (the Zicclsm extension), the hardware runs the access when it falls in the main memory, which is everything that is neither the Boot memory nor the direct FLASH. An access that fits in one word (`LH`, `LHU` and `SH` with `ea[1:0] = "01"`) completes in one cycle, and an access that spans two words (`LW` and `SW` at offsets 1 to 3, `LH`, `LHU` and `SH` at offset 3) runs in two steps in the `misaligned_unit`. In step 1 the pipeline waits and the unit presents the word of the first byte, in step 2 it presents the next word, and the WB stage joins the two words of a load. An access that crosses the word is not atomic, because the first half may have been written when the second fails. The two words must lie in the same region, and an access outside the main memory or between regions is an access that the hardware does not run. With `HAS_ZICSR = true`, `src/Zicsr/trap_unit.vhd` detects that access in the EX stage, annuls the instruction before it reaches the MEM stage (`flush_ex_mem = '1'`), and raises a synchronous exception with `mcause = 4` (Load Address Misaligned) or `mcause = 6` (Store Address Misaligned), writing the effective address `i_ea` to `mtval`. With `HAS_ZICCLSM = false` every misaligned access is an access that the hardware does not run, and that combination requires `HAS_ZICSR = true`, otherwise elaboration fails.

## 5. Exceptions Without Zicsr

Without Zicsr the core has no CSRs to record an exception. The cause detector stays active, and an exception is signalled on outputs of the `core`, without redirecting the PC.

| Output | Meaning |
| :--- | :--- |
| `o_trap` | One-cycle pulse at `'1'` when an exception occurs |
| `o_trap_cause` | Cause code in the `mcause` format (2 illegal instruction, 3 `EBREAK`, 4 and 6 misaligned access that the hardware does not run, 11 `ECALL`) |
| `o_trap_pc` | PC of the instruction that raised the exception |
| `o_trap_take` | One-cycle pulse at `'1'` when the core takes an exception, with or without Zicsr (with Zicsr, `o_trap` stays at `'0'` and this pulse is the only external signal) |

The instruction that raised the exception is annulled in the EX stage, with no write to `rd` and no memory access, and the program goes on at the next instruction. Any CSR instruction is illegal without Zicsr, and a jump to a misaligned address is not checked. With Zicsr, `o_trap` stays at `'0'` and the other two outputs stay at zero. The environment around the core decides what to do with the signal.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
