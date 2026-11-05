# Zicsr: Core Implementation

This document describes how the Core implements the `Zicsr` extension and the machine-mode synchronous exception handling that depends on it. The RISC-V manual requirements are in [instructions.md](instructions.md). The counters accessed through CSRs (`Zicntr` and `Zihpm`) are documented in [Zicntr](../Zicntr/description.md) and [Zihpm](../Zihpm/description.md) and are not covered here.

## 1. Overview

The extension is enabled by the `has_zicsr` generic of the `core` entity (default `false`) and brings together three blocks.

| Block | Stage | Function |
| :--- | :--- | :--- |
| `csr_decode` | ID | Recognizes the `SYSTEM` class, marks the six CSR access instructions and forces extraction of the I-type immediate |
| `csr_file` | EX | Holds the CSRs, reads the old value and applies the write at the end of the cycle |
| `trap_unit` | EX and MEM | Detects synchronous exceptions and the `MRET` return |

The packages `csr_addr_consts`, `csr_value_consts`, `trap_consts` and `irq_consts` define the CSR addresses, the operation codes and `misa` values, and the constants for `ECALL`, `EBREAK`, `MRET`, `WFI` and `mcause`, plus the bit positions and causes of the machine interrupts. The Core implements only machine mode, and `mstatus.MPP` always reads `11`.

## 2. Decoding in the ID Stage

`csr_decode` examines the instruction `opcode` and `funct3`.

| Condition | `o_is_csr` | `o_we_reg` | `o_use_imm_i` |
| :--- | :---: | :---: | :---: |
| `opcode = SYSTEM` and `funct3` different from `000` and `100` (the six CSR instructions) | `1` | `1` | `1` |
| `opcode = SYSTEM` and `funct3` equal to `000` (`ECALL`, `EBREAK`, `MRET`, `WFI`) or `100` (reserved) | `0` | `0` | `1` |
| Any other `opcode` | `0` | `0` | `0` |

The `o_use_imm_i` signal forces the immediate extender to produce the I-type field (`instr[31:20]`), which carries the 12-bit CSR address (or the `funct12` of the privileged instructions) to the EX stage. The `o_we_reg` signal enables the write of `rd` with the old CSR value. The hazard detection unit counts `SYSTEM` among the instructions that read `rs1`, and inserts one stall cycle when an immediately preceding load produces that register.

## 3. Execution in the EX Stage

### 3.1. Operand and Commit Point

The write operand depends on bit 2 of `funct3`.

| `funct3[2]` | Instructions | Operand $S$ |
| :---: | :--- | :--- |
| `0` | `CSRRW`, `CSRRS`, `CSRRC` | `rs1` value, already forwarded |
| `1` | `CSRRWI`, `CSRRSI`, `CSRRCI` | `rs1` index (5 bits) zero-extended to 32 bits |

The write is committed on the clock rising edge in which the instruction is valid in EX and the pipeline advances, according to the condition below.

$$\text{commit} = \text{is\_csr} \land \text{valid} \land \text{pipe\_run}$$

The old value leaves the file through a combinational read and enters the same result multiplexer as the ALU and the multiplier, so it crosses `EX/MEM` and `MEM/WB` and is forwarded like any ALU result, with no extra cycles. The next instruction reads the already updated CSR.

### 3.2. Write Rules

The file decides the operation from bits `[1:0]` of `funct3`.

| `funct3[1:0]` | Operation | New value |
| :---: | :--- | :--- |
| `01` | Write | $C' = S$ |
| `10` | Bit set | $C' = C \lor S$ |
| `11` | Bit clear | $C' = C \land \lnot S$ |

The source is considered null when the `rs1` field of the instruction is `x0` (in the immediate forms, `uimm = 0`). An instruction has write effect when it is a write (`CSRRW` and `CSRRWI`, even with `rd = x0`) or when the source is not null. With `rs1 = x0`, `CSRRS` and `CSRRC` read without writing and raise no exception on read-only CSRs, as the manual requires. The file always reads the CSR, including in `CSRRW` with `rd = x0`; since no Core CSR has a read side effect, the difference is not observable.

### 3.3. Illegal Access

The file flags an illegal access when the expression below holds.

$$\text{illegal} = \lnot\,\text{known\_address} \;\lor\; (\text{has\_write\_effect} \land \text{addr}[11{:}10] = 11)$$

An illegal access becomes an illegal-instruction exception (section 5). A write changes state only when the address is known, the CSR is not read-only and `commit` holds, and, for `mtvec`, `mscratch`, `mepc`, `mcause` and `mtval`, no trap, `MRET` or MEM-stage exception occurs in the same cycle.

## 4. CSR File

The addresses and names of the CSRs are not a choice of the Core. They come from the machine-level CSR table of the privileged architecture manual ([Currently allocated RISC-V machine-level CSR addresses](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-4-currently-allocated-risc-v-machine-level-csr-addresses)), and the convention of the address bits (read and write in bits [11:10], privilege in bits [9:8]) is in [section 1.1.1 of the same volume](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-1-csr-address-mapping-conventions). The Access column follows the classes of the table, with R for `MRO` (read-only) and R/W for `MRW` (read and write), and the Definition column leads to the manual section that describes each register. The Core implements only a subset of the table.

All CSRs are zero after reset, except `misa` and the fixed part of `mstatus`, which are constants. The Write column describes the effect of an effective write.

| Address | CSR | Access | Definition | Read | Write |
| :---: | :--- | :---: | :---: | :--- | :--- |
| `0x300` | `mstatus` | R/W | [2.1.1.6](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-6-machine-status-mstatus-and-mstatush-registers) | `MPP` (bits 12 and 11) fixed at `11`, `MPIE` (bit 7), `MIE` (bit 3); other bits zero | Only `MIE` and `MPIE` are stored; other bits are ignored |
| `0x301` | `misa` | R/W | [2.1.1.1](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#misa) | `0x40000100` (`MXL = 1`, extension `I`); with `has_m`, `0x40001100` (adds bit 12, extension `M`); with `has_e` true (RV32E), bit 4 (extension `E`) replaces bit 8, and the value is `0x40000010` or, with `has_m`, `0x40001010` | Ignored |
| `0x304` | `mie` | R/W | [2.1.1.9](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-9-machine-interrupt-mip-and-mie-registers) | Zero; with `has_interrupts`, the masks `MSIE`, `MTIE` and `MEIE` (bits 3, 7 and 11) | With `has_interrupts`, writes bits 3, 7 and 11; the other bits are ignored |
| `0x305` | `mtvec` | R/W | [2.1.1.7](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-7-machine-trap-vector-base-address-mtvec-register) | Handler base address, with bits `[1:0]` at zero | Stores bits `[31:2]`; the mode is always direct |
| `0x310` | `mstatush` | R/W | [2.1.1.6](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-6-machine-status-mstatus-and-mstatush-registers) | Zero | Ignored |
| `0x340` | `mscratch` | R/W | [2.1.1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-13-machine-scratch-mscratch-register) | Stored value, 32 bits | Stores all 32 bits |
| `0x341` | `mepc` | R/W | [2.1.1.14](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-14-machine-exception-program-counter-mepc-register) | Saved PC, with bits `[1:0]` at zero | Stores bits `[31:2]` |
| `0x342` | `mcause` | R/W | [2.1.1.15](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#mcause) | Code of the last exception, 32 bits | Stores all 32 bits |
| `0x343` | `mtval` | R/W | [2.1.1.16](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-16-machine-trap-value-mtval-register) | Value associated with the last exception, 32 bits | Stores all 32 bits |
| `0x344` | `mip` | R/W | [2.1.1.9](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-9-machine-interrupt-mip-and-mie-registers) | Zero; with `has_interrupts`, the level of the `MSIP`, `MTIP` and `MEIP` lines (bits 3, 7 and 11) | Ignored |
| `0xF11` | `mvendorid` | R | [2.1.1.2](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-2-machine-vendor-id-mvendorid-register) | Zero | Effective write is illegal |
| `0xF12` | `marchid` | R | [2.1.1.3](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-3-machine-architecture-id-marchid-register) | Zero | Effective write is illegal |
| `0xF13` | `mimpid` | R | [2.1.1.4](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-4-machine-implementation-id-mimpid-register) | Zero | Effective write is illegal |
| `0xF14` | `mhartid` | R | [2.1.1.5](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-5-hart-id-mhartid-register) | Zero | Effective write is illegal |
| `0xF15` | `mconfigptr` | R | [2.1.1.17](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-17-machine-configuration-pointer-mconfigptr-register) | Zero | Effective write is illegal |

The counter addresses (`mcountinhibit`, `mhpmeventN`, `mcycle`, `minstret`, `mhpmcounterN`, `cycle`, `time`, `instret` and the high halves) also come from the table of the privileged manual, and exist only when the profile includes `Zicntr` or `Zihpm`, described in [Zicntr](../Zicntr/description.md) and [Zihpm](../Zihpm/description.md). Without them, those addresses are not known and the access is illegal. Any other address is also not known. Without `has_interrupts`, `mie` and `mip` read zero and ignore writes.

### 4.1. Machine Interrupts

The `has_interrupts` generic (default `false`, requires `has_zicsr`) turns on the three machine interrupt lines of the `core` and makes `mip` and `mie` work. The lines are level signals in the clock domain of the core; a source in another domain goes first through a `synchronizer` of `Common-Components`.

| Port | Interrupt | Bit in `mip` and `mie` |
| :--- | :--- | :---: |
| `i_irq_software` | Machine software (`MSIP`, `MSIE`) | 3 |
| `i_irq_timer` | Machine timer (`MTIP`, `MTIE`) | 7 |
| `i_irq_external` | Machine external (`MEIP`, `MEIE`) | 11 |

The `mip` register is read-only and reads the current level of the three lines at bits 3, 7 and 11; the other bits read zero. A write to `mip` is legal and changes nothing. The `mie` register holds bits 3, 7 and 11; the other bits read zero and ignore the write, and the value after reset is zero. A write to `mie` follows the general rules of section 3.2 and does not happen in the cycle of a trap or an `MRET`.

The `o_irq_pending` output of the `csr_file` tells that an interrupt is pending and enabled in `mie`, regardless of `mstatus.MIE`.

$$\text{o\_irq\_pending} = \left(\text{mip} \land \text{mie}\right) \ne 0$$

With `has_interrupts = false`, the ports are ignored, `mie` and `mip` read zero and ignore writes, and `o_irq_pending` is `0`. The bit positions and the `mcause` code of each interrupt are in the `irq_consts` package: `0x80000003` (software), `0x80000007` (timer) and `0x8000000B` (external).

## 5. Synchronous Exceptions

### 5.1. Generated Causes

`trap_unit` evaluates the instruction in the EX stage and flags at most one exception per instruction, only when the instruction is valid and the pipeline advances.

| `mcause` | Exception | Condition | `mtval` |
| :---: | :--- | :--- | :--- |
| 0 | Instruction address misaligned | Taken branch, `JAL` or `JALR` with target bits `[1:0]` different from `00` | Target address |
| 2 | Illegal instruction | Undefined encoding flagged by the ID-stage decoder, unsupported `SYSTEM` instruction, or illegal CSR access (section 3.3) | Zero |
| 3 | Breakpoint | `EBREAK` (`funct12 = 0x001`) | Zero |
| 4 | Load address misaligned | Misaligned load that the hardware does not execute | Effective address |
| 6 | Store address misaligned | Misaligned store that the hardware does not execute | Effective address |
| 11 | Machine-mode environment call | `ECALL` (`funct12 = 0x000`) | Zero |

The `ECALL`, `EBREAK`, `MRET` and `WFI` instructions are recognized only with `funct3 = 000`, `rd = x0` and `rs1 = x0`. Any other non-CSR `SYSTEM` instruction, including `funct3 = 100`, `SRET` and `SFENCE.VMA`, is illegal. The ID-stage decoder also flags as illegal a register index above 15 when the profile is RV32E.

A load or store misalignment is defined by the rules of the `Zicclsm` extension: the hardware executes the misaligned access inside main memory (internal RAM and SDRAM) when `has_zicclsm = true`, and any other misalignment raises causes 4 and 6. With `has_zicsr = true`, these two causes are checked in the MEM stage by a second `trap_unit` instance, which reads the effective address already registered in `EX/MEM`, and the EX-stage instance does not check the effective address.

### 5.2. Priority

For the EX-stage instance, the priority is the one in the table, from top to bottom.

| Priority | `mcause` |
| :---: | :---: |
| 1 | 0 |
| 2 | 2 |
| 3 | 3 |
| 4 | 11 |

The load or store exception (causes 4 and 6) belongs to an instruction older than the one in the EX stage and therefore has priority over all EX causes. When it occurs, the EX instruction is discarded entirely, with no CSR write, branch, `MRET`, `FENCE.I` or retirement.

### 5.3. Handler Entry

When an exception is taken, the CSR file performs the following actions in the same cycle.

1. `mepc` receives the PC of the faulting instruction, with the two low bits cleared.
2. `mcause` receives the cause code and `mtval` receives the associated value.
3. `mstatus.MPIE` receives `mstatus.MIE`, and `mstatus.MIE` goes to zero.
4. The PC takes the value of `mtvec`.

If the exception occurs in the MEM stage, the PC saved in `mepc` is that of the load or store instruction, carried in `EX/MEM`.

### 5.4. Return with MRET

The `MRET` instruction (`funct12 = 0x302`) is detected in EX. It restores `mstatus.MIE` with the value of `mstatus.MPIE`, sets `mstatus.MPIE` to `1` and redirects the PC to `mepc`. The `WFI` instruction (`funct12 = 0x105`) is accepted as a legal instruction and does nothing.

### 5.5. Redirection and Flush

The redirect PC is chosen among `mepc` (on `MRET`), `PC + 4` (on `FENCE.I`) and `mtvec` (on exception). The PC selector gives redirection the highest priority over branches and `JALR`, and the PC register accepts the new value even with the pipeline frozen.

| Event | Registers flushed | Note |
| :--- | :--- | :--- |
| Exception in EX | `IF/ID`, `ID/EX`, `EX/MEM` | The faulting instruction neither writes `rd` nor accesses memory |
| Exception in MEM | `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` | The faulting access does not reach memory and the EX instruction is discarded |
| `MRET` | `IF/ID`, `ID/EX` | `MRET` itself continues in the pipeline as an instruction with no register effect |

### 5.6. Latency

The EX exception is detected combinationally in the cycle in which the instruction is in EX and the pipeline advances. The CSRs and the PC are written at the clock edge that ends that cycle, so the first handler instruction is fetched in the following cycle. Two younger instructions (in the IF and ID stages) are discarded, besides the faulting instruction itself. The load or store exception is detected in the cycle in which the access reaches MEM, one cycle after the instruction passed through EX.

The retirement of an instruction in EX adds to `minstret` one cycle later, and a MEM exception cancels that addition, so the failing access does not count as retired. Counter details are in [Zicntr](../Zicntr/description.md) and [Zihpm](../Zihpm/description.md).

## 6. Core without Zicsr

With `has_zicsr = false`, `csr_file` and `csr_decode` are not instantiated and there are no trap registers. The Core keeps a cause detector that only flags the exception on its outputs and does not redirect the PC.

| Output | Value |
| :--- | :--- |
| `o_trap` | One-cycle pulse at `1` when an exception occurs; stays at `0` with Zicsr |
| `o_trap_cause` | Cause code in the `mcause` format; stays at zero with Zicsr |
| `o_trap_pc` | PC of the instruction that raised the exception; stays at zero with Zicsr |

In this mode, every CSR access instruction is illegal (cause 2), `ECALL` raises cause 11 and `EBREAK` cause 3, and load and store misalignment (causes 4 and 6) is checked in the EX stage itself. Branch target misalignment is not checked, and `MRET` has no effect. The faulting instruction is annulled in EX, with no `rd` write and no memory access, and the program continues at the next instruction. The instruction that raised the exception does not count as retired. The environment around the Core decides what to do with the signal.

A core with neither `Zicsr` nor `Zicclsm` is valid: the misaligned access is only signalled on `o_trap`. `Zicntr` and `Zihpm` require `Zicsr`, and elaboration fails without it.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
