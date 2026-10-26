# 2. Bus Interface and Memory Map

## 1. Processor Address Map

The bounds of the instruction address space (IF stage) and data address space (MEM and WB stages) are centralized in the `common/mem_map_consts.vhd` package:

| Constant (`mem_map_consts`) | Value | Demarcated region |
| :--- | :--- | :--- |
| `BOOT_ROM_SIZE_BYTES` | `0x00000800` (2 KiB) | End of the Boot ROM window (`0x00000000 .. 0x000007FF`) in the IF stage |
| `RAM_BASE_BYTES` | `0x00008000` (32 KiB) | Base of internal data RAM (`0x00008000 .. 0x3FFFFFFF`); data addresses below this bound access port 2 of Flash memory |
| `SDRAM_BASE_BYTES` | `0x40000000` (1 GiB) | Base of the external SDRAM and memory-mapped peripheral window (`0x40000000 .. 0xFFFFFFFF`) |

## 2. Instruction Fetch Interfaces (IF Stage)

The IF stage (`core/stage_if.vhd`) presents the current PC address on `o_if_addr` with `o_if_rden = '1'` and selects the fetched instruction according to the address range:

| Port on top level `core` | Direction | Address region | Description |
| :--- | :--- | :--- | :--- |
| `o_if_addr` | `out` | All | Byte address of the current Program Counter |
| `o_if_rden` | `out` | All | Instruction read enable (hardwired to `'1'`) |
| `i_boot_rom_data` | `in` | `< 0x00000800` | 32-bit instruction word returned by the Boot ROM |
| `i_flash_data` | `in` | `0x00000800 .. 0x3FFFFFFF` | 32-bit instruction word returned by port 1 of Flash memory |
| `o_ic_sel` | `out` | `>= 0x40000000` | Indicates that the current PC points to the region served by the external instruction cache (SDRAM) |
| `i_ic_data` | `in` | `>= 0x40000000` | 32-bit instruction word supplied by the external instruction cache |
| `i_ic_ready` | `in` | `>= 0x40000000` | Signals that `i_ic_data` holds a valid instruction for `o_if_addr`; while `'0'` with `o_ic_sel = '1'`, the PC freezes and `reg_if_id` receives a bubble (`i_valid = '0'`) |
| `o_ic_inval` | `out` | Cache control | 1-cycle pulse generated upon completion of a `FENCE.I` instruction to invalidate the external instruction cache |

## 3. Data Memory Interfaces (MEM and WB Stages)

In the MEM stage (`core/stage_mem.vhd`), the effective address computed in the EX stage is routed to one of three data interfaces. In the WB stage (`core/stage_wb.vhd`), the corresponding read datum is selected and aligned by `I/extender_ram.vhd`.

### 3.1. Flash Memory Data Port (`< 0x00008000`)

Used for reading constants (`.rodata`) and copying the `.data` section at startup, with a fixed 1-cycle synchronous latency:

| Port on top level `core` | Direction | Stage | Meaning |
| :--- | :--- | :--- | :--- |
| `o_flash_addr2` | `out` | MEM | Byte address of the Flash read |
| `o_flash_rden2` | `out` | MEM | Read enable (`exmem_re_ram and exmem_valid and is_flash_data`) |
| `i_flash_data2` | `in` | WB | 32-bit word returned on the next cycle |

### 3.2. Internal RAM (`0x00008000 .. 0x3FFFFFFF`)

1-cycle synchronous data memory with byte-mask controlled writes:

| Port on top level `core` | Direction | Stage | Meaning |
| :--- | :--- | :--- | :--- |
| `o_ram_addr` | `out` | MEM | Byte address of the access |
| `o_ram_wdata` | `out` | MEM | 32-bit word with write bytes positioned by `store_manager` |
| `o_ram_byteena` | `out` | MEM | 4-bit mask indicating which bytes of `o_ram_wdata` must be written |
| `o_ram_en` | `out` | MEM | Overall enable for internal RAM |
| `o_ram_wren` | `out` | MEM | Write enable for internal RAM |
| `o_ram_rden` | `out` | MEM | Read enable for internal RAM |
| `i_ram_rdata` | `in` | WB | 32-bit word read from internal RAM on the next cycle |

### 3.3. Variable-Latency External Bus: SDRAM and Peripherals (`>= 0x40000000`)

Every read or write access with an address at or above `0x40000000` uses the processor's external master port:

| Port on top level `core` | Direction | Stage | Meaning |
| :--- | :--- | :--- | :--- |
| `o_sdram_addr` | `out` | MEM | Byte address of the external access |
| `o_sdram_wdata` | `out` | MEM | 32-bit datum aligned for writing |
| `o_sdram_byteena` | `out` | MEM | Byte enable mask (4 bits) |
| `o_sdram_rden` | `out` | MEM | Read request active while the valid access remains in MEM |
| `o_sdram_wren` | `out` | MEM | Write request active while the valid access remains in MEM |
| `i_sdram_rdata` | `in` | WB | 32-bit word returned by the external slave |
| `i_sdram_ready` | `in` | MEM | Logic level indicating completion of the external transaction (`'0'` holds the pipeline; defaults to `'1'` when unconnected) |
| `o_mem_advance` | `out` | Global | Signals to the external slave that the MEM stage is advancing on the current clock edge (`base_run = '1'`) |

External handshake protocol rules:

1. **Stability during wait:** while `sdram_access = '1'` and `i_sdram_ready = '0'`, `o_sdram_wait` keeps `base_run = '0'`, freezing `reg_ex_mem` and holding `o_sdram_addr`, `o_sdram_wdata`, `o_sdram_byteena`, `o_sdram_rden`, and `o_sdram_wren` stable.
2. **Level acknowledgment (`i_sdram_ready`):** the external slave must hold `i_sdram_ready = '1'` until it observes `o_mem_advance = '1'`, ensuring that completion is not lost if the `multdiv` unit is also stalling the pipeline on the same cycle.
3. **Read-data preservation (`i_sdram_rdata`):** the `i_sdram_rdata` word remains stable until the WB cycle in which the load instruction is consumed by `stage_wb`.
4. **Branch-flush inhibition during wait:** branches and jumps taken in the EX stage flush `reg_if_id` and `reg_id_ex` only when `pipe_run = '1'`, preserving the branch instruction in EX until the access in MEM completes.

## 4. Sub-Word Alignment and Misalignment Exceptions

The data bus always operates on 32-bit words accompanied by `byteena`:

- **Naturally aligned accesses (`LB`/`LBU`/`SB` at any address, `LH`/`LHU`/`SH` at even addresses, `LW`/`SW` at multiples of 4):** on a store, `I/store_manager.vhd` replicates the byte or halfword across the byte lanes selected by `ea[1:0]` and asserts the corresponding bits of `o_byte_mask`; on a load, `I/extender_ram.vhd` extracts the slice selected by `ea[1:0]` and applies sign or zero extension in the WB stage.
- **Misaligned accesses (`LW`/`SW` with `ea[1:0] /= "00"` or `LH`/`LHU`/`SH` with `ea[0] = '1'`):** when `has_zicsr = true`, `Zicsr/trap_unit.vhd` detects the misalignment in the EX stage, annuls the instruction before it reaches the MEM stage (`flush_ex_mem = '1'`), and raises a synchronous exception with `mcause = 4` (Load Address Misaligned) or `mcause = 6` (Store Address Misaligned), writing the effective address `i_ea` to `mtval`.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
