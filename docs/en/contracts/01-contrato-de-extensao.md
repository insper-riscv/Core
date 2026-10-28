# 1. RV32 Pipeline Extension Contract

## 1. Contract Scope

The RISC-V specification defines the architectural semantics of each instruction (opcodes, `funct3`/`funct7` fields, and register effects). The extension contract defines how the hardware of an extension (`M/`, `Zicsr/`, `Zifencei/`) connects to the pipeline stages (`core/`) without coupling the base logic (`common/` and `I/`) to the internal details of each extension.

Each extension resides in its own folder and is enabled at the top level `core/core.vhd` by a boolean generic (`has_m`, `has_zmmul`, `has_zicsr`, `has_zifencei`, `has_dcache`). When the corresponding generic is `false`, the instructions of that extension behave as `NOP` (no register write, no memory access, and no pipeline stall).

## 2. Pipeline Integration Rules

### 2.1. Decoding in the ID Stage

The base control unit (`common/control_unit.vhd`) decodes exclusively the RV32I base instruction set. Instructions belonging to optional extensions are claimed by dedicated decoders conditionally instantiated in `core/stage_id.vhd`:

| Extension | Decoder in `stage_id` | Claim condition | Activated signals |
| :--- | :--- | :--- | :--- |
| `M` | `M/m_decode.vhd` | `opcode = OPCODE_OP` (`"0110011"`) and `funct7 = FUNCT7_MULDIV` (`"0000001"`) | `o_is_muldiv = '1'`, `o_we_reg = '1'`, `o_sel_pc_rs1 = '1'` |
| `Zicsr` | `Zicsr/csr_decode.vhd` | `opcode = OPCODE_SYSTEM` (`"1110011"`) | `o_use_imm_i = '1'` for the entire `SYSTEM` class; `o_is_csr = '1'` and `o_we_reg = '1'` when `funct3` is neither `"000"` nor `"100"` |

The ID stage combines write enables by logical disjunction (`cu_we_reg <= base_we_reg or m_we_reg or csr_we_reg`) and propagates the `o_is_muldiv` and `o_is_csr` indicators through the `reg_id_ex` barrier register into the EX stage.

### 2.2. Permitted Pipeline Effects

An extension interacts with global pipeline control in `core/core.vhd` exclusively through three mechanisms:

1. **Multi-cycle busy stall (`o_muldiv_stall` / `o_fencei_busy`):** freezes earlier stages while the operation awaits completion.
2. **Flow discard and redirection (`o_fencei_take`, `o_mret_take`):** flushes `reg_if_id` and `reg_id_ex` and redirects the PC to `o_redirect_pc`.
3. **Synchronous exception (`o_trap_take`):** in addition to flushing `reg_if_id` and `reg_id_ex` and redirecting the PC to `mtvec`, flushes `reg_ex_mem` to prevent the faulting instruction from modifying registers or memory.

### 2.3. Result Path and Forwarding

In the EX stage (`core/stage_ex.vhd`), the result produced by the extension (`ex_muldiv_result` when `i_is_muldiv = '1'` or `csr_rdata` when `i_is_csr = '1'`) is multiplexed into `ex_alu_mux_result` alongside `ex_alu_result`. As a result, the value traverses `reg_ex_mem` and `reg_mem_wb` and is served by the forwarding network (`forwarding_unit`) without special paths in the register file.

## 3. Specification per Extension

### 3.1. M Extension (`M/multdiv.vhd`)

The `multdiv` unit encapsulates the radix-2 Booth multiplier (`booth_multiplier_rv32`), the 34-bit non-restoring divider (`non_restoring_divider_rv32`), and the start and hold control logic:

| `multdiv` port | Direction | Behavior |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | `in` | Main clock and active-high reset (`'1'`) |
| `i_valid`, `i_is_muldiv` | `in` | Indicate a valid M-extension instruction present in the EX stage |
| `i_funct3` | `in` | Selects the operation (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`) and is latched internally at the start of the calculation |
| `i_a`, `i_b` | `in` | `rs1` and `rs2` operands already resolved by the forwarding multiplexers |
| `o_result` | `out` | 32-bit result registered on the clock edge where `o_done = '1'` |
| `o_busy` | `out` | Asserts combinationally on the start cycle itself (*eager stall*) and stays `'1'` throughout the iteration cycles |
| `o_done` | `out` | 1-cycle pulse at the end of the calculation |
| `o_stall` | `out` | Active while `o_busy = '1'` or `o_done = '1'`, keeping the pipeline held until `o_result` is captured |

### 3.2. Zicsr Extension and Exceptions (`Zicsr/csr_file.vhd` and `Zicsr/trap_unit.vhd`)

The `rv32im_zicsr` profile enables `has_zicsr = true`. The CSR file and trap unit operate in the EX stage:

| Aspect | Specification |
| :--- | :--- |
| CSR read | Combinational on `o_rdata`, returning the value prior to the instruction's write |
| CSR write | Committed on the rising clock edge when `i_commit = i_is_csr and i_valid and i_pipe_run = '1'` with no active exception; `CSRRW`/`CSRRWI` always write, whereas `CSRRS`/`CSRRC` and their immediate forms write only if `i_src_zero = '0'` |
| Write operand | `ex_fwd_rs1_val` for register instructions (`i_funct3(2) = '0'`) or the 5-bit `i_rs1_idx` zero-extended to 32 bits for immediate forms (`i_funct3(2) = '1'`) |
| Load-use hazard | The `hazard_detection_unit` includes `OPCODE_SYSTEM` among `rs1` readers, inserting a 1-cycle stall when preceded by a load to the same register |
| Illegal access | `csr_file` asserts `o_illegal = '1'` for unimplemented CSR addresses or effective write attempts to read-only CSRs (`i_addr[11:10] = "11"`) |
| `misa` | Reads RV32I, plus the M extension (bit 12) when `has_m = true`; Zmmul has no bit of its own; writes are ignored |
| Not implemented | `cycle`, `time` and `instret` (an access is an illegal CSR access) and interrupts (`mie` and `mip` read zero and ignore writes) |

Synchronous exceptions detected by `trap_unit` (at most one per instruction, with top-to-bottom priority). The `control_unit` flags an undefined encoding in the ID stage, `m_decode` clears the flag for the M instructions, and the flag reaches EX through `reg_id_ex`. Without `has_zicsr` there is no trap unit, and an undefined encoding executes as a `NOP`:

| Code (`o_cause`) | Exception | Value written to `mtval` (`o_tval`) |
| ---: | :--- | :--- |
| `0` | Taken branch or jump target address with bits `[1:0] /= "00"` | Misaligned target address (`i_cf_target`) |
| `2` | Unsupported `SYSTEM` instruction (`funct3 = "100"`, `SRET`, `SFENCE.VMA`, or `ECALL`/`EBREAK`/`MRET`/`WFI` with `rd /= x0` or `rs1 /= x0`), illegal CSR access (`i_csr_illegal = '1'`), or any encoding that RV32IM does not define (`i_illegal = '1'`: a reserved opcode, an invalid `funct3` or `funct7`, all zeros, all ones, a compressed encoding, or `FENCE.I` when `has_zifencei = false`) | `0x00000000` |
| `3` | Breakpoint (`EBREAK`, `imm12 = 0x001`) | `0x00000000` |
| `4` | Misaligned Load effective address that the hardware does not run: outside the main memory (flash and peripherals), with the two words in different regions (internal RAM and SDRAM), or any misaligned load with `has_zicclsm = false` | Effective address (`i_ea`) |
| `6` | Misaligned Store effective address that the hardware does not run, under the same conditions as cause 4 | Effective address (`i_ea`) |
| `11` | Machine-mode environment call (`ECALL`, `imm12 = 0x000`) | `0x00000000` |

When taking an exception (`o_take = '1'`), `mepc` receives the instruction's PC, `mcause` receives `o_cause`, `mtval` receives `o_tval`, `mstatus.MPIE` receives `mstatus.MIE`, `mstatus.MIE` is cleared, and the PC jumps to `mtvec`. On `MRET` (`0x30200073`), `mstatus.MIE` restores `mstatus.MPIE`, `mstatus.MPIE` receives `'1'`, and the PC jumps to `mepc`. The `WFI` instruction (`0x10500073`) executes as a `NOP`.

Machine-mode CSRs implemented:

| Address | Name | Access | Reset Value | Mask / Implemented fields |
| :--- | :--- | :--- | :--- | :--- |
| `0x300` | `mstatus` | Read-write | `0x00001800` | `MPP` (bits `[12:11]`) hardwired to `"11"`; `MIE` (bit 3) and `MPIE` (bit 7) writable |
| `0x301` | `misa` | Read-only | `0x40001100` | RV32 (`MXL = 1`) with `I` and `M` extensions |
| `0x304`, `0x344` | `mie`, `mip` | `mie` RW, `mip` RO | `0x00000000` | All bits hardwired to zero |
| `0x305` | `mtvec` | Read-write | `0x00000000` | Bits `[1:0]` hardwired to `"00"` (direct mode) |
| `0x310` | `mstatush` | Read-write | `0x00000000` | All bits hardwired to zero |
| `0x340`, `0x342`, `0x343` | `mscratch`, `mcause`, `mtval` | Read-write | `0x00000000` | Full 32 bits |
| `0x341` | `mepc` | Read-write | `0x00000000` | Bits `[1:0]` hardwired to `"00"` |
| `0xF11`..`0xF15` | `mvendorid`, `marchid`, `mimpid`, `mhartid`, `mconfigptr` | Read-only | `0x00000000` | Read constantly as zero |

### 3.3. Zifencei Extension (`Zifencei/fencei_unit.vhd`)

The `rv32im_zicsr_zifencei` profile enables `has_zifencei = true`:

| Aspect | Behavior |
| :--- | :--- |
| Instruction fetch from SDRAM (`>= 0x40000000`) | The IF stage asserts `o_ic_sel = '1'` and reads `i_ic_data`. While `i_ic_ready = '0'`, the PC stays frozen and `o_instr_valid = '0'` injects bubbles into `reg_if_id`, while EX, MEM, and WB continue advancing |
| `FENCE.I` execution without D-cache (`has_dcache = false`) | When `FENCE.I` is valid in EX and `i_base_run = '1'`, `o_take` pulses for 1 cycle, asserting `o_ic_inval = '1'`, flushing `IF/ID` and `ID/EX`, and redirecting the PC to $\text{PC} + 4$ |
| `FENCE.I` execution with write-back D-cache (`has_dcache = true`) | The unit holds the instruction in EX for one cycle, so that the older stores leave MEM and reach the cache, emits a pulse on `o_dc_flush` (`o_flush_req`) and holds `o_busy = '1'` (freezing PC, `IF/ID`, and `ID/EX` and injecting bubbles into `EX/MEM`) until `i_dc_done = '1'` is received, which the cache may raise in the very cycle of the pulse on `o_dc_flush` or in any later cycle, at which point it pulses `o_take = '1'` and invalidates the I-cache |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
