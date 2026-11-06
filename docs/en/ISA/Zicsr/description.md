# Zicsr: Core Implementation

This document describes how the Core implements the `Zicsr` extension and the machine-mode synchronous exception handling that depends on it. The RISC-V manual requirements are in [instructions.md](instructions.md). The counters accessed through CSRs (`Zicntr` and `Zihpm`) are documented in [Zicntr](../Zicntr/description.md) and [Zihpm](../Zihpm/description.md) and are not covered here.

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 5, Zicsr Extension for Control and Status Register (CSR) Instructions, version 2.0 |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |
| Chapters of the privileged volume | 2, Control and Status Registers (CSRs), and 3, Machine-Level ISA, in sections 3.1.6 to 3.1.16 (trap CSRs), 3.3 (`ECALL`, `EBREAK`, `MRET`, `WFI`) and Table 17 (exception priority) |
| Conformance with the privileged volume | `docs/conformance/riscv-privilegiado.md` of Insper-RISC-V |

## 2. Overview

The extension is enabled by the `has_zicsr` generic of the `core` entity (default `false`) and brings together three blocks.

| Block | Stage | Function |
| :--- | :--- | :--- |
| `csr_decode` | ID | Recognizes the `SYSTEM` class, marks the six CSR access instructions and forces extraction of the I-type immediate |
| `csr_file` | EX | Holds the CSRs, reads the old value and applies the write at the end of the cycle |
| `trap_unit` | EX and MEM | Detects synchronous exceptions and the `MRET` return |

The packages `csr_addr_consts`, `csr_value_consts`, `trap_consts` and `irq_consts` define the CSR addresses, the operation codes and `misa` values, and the constants for `ECALL`, `EBREAK`, `MRET`, `WFI` and `mcause`, plus the bit positions and causes of the machine interrupts. The Core implements only machine mode, and `mstatus.MPP` always reads `11`.

## 3. Decoding in the ID Stage

`csr_decode` examines the instruction `opcode` and `funct3`.

| Condition | `o_is_csr` | `o_we_reg` | `o_use_imm_i` |
| :--- | :---: | :---: | :---: |
| `opcode = SYSTEM` and `funct3` different from `000` and `100` (the six CSR instructions) | `1` | `1` | `1` |
| `opcode = SYSTEM` and `funct3` equal to `000` (`ECALL`, `EBREAK`, `MRET`, `WFI`) or `100` (reserved) | `0` | `0` | `1` |
| Any other `opcode` | `0` | `0` | `0` |

The `o_use_imm_i` signal forces the immediate extender to produce the I-type field (`instr[31:20]`), which carries the 12-bit CSR address (or the `funct12` of the privileged instructions) to the EX stage. The `o_we_reg` signal enables the write of `rd` with the old CSR value. The hazard detection unit counts `SYSTEM` among the instructions that read `rs1`, and inserts one stall cycle when an immediately preceding load produces that register.

## 4. Execution in the EX Stage

### 4.1. Operand and Commit Point

The write operand depends on bit 2 of `funct3`.

| `funct3[2]` | Instructions | Operand $S$ |
| :---: | :--- | :--- |
| `0` | `CSRRW`, `CSRRS`, `CSRRC` | `rs1` value, already forwarded |
| `1` | `CSRRWI`, `CSRRSI`, `CSRRCI` | `rs1` index (5 bits) zero-extended to 32 bits |

The write is committed on the clock rising edge in which the instruction is valid in EX and the pipeline advances, according to the condition below.

$$\text{commit} = \text{is\_csr} \land \text{valid} \land \text{pipe\_run}$$

The old value leaves the file through a combinational read and enters the same result multiplexer as the ALU and the multiplier, so it crosses `EX/MEM` and `MEM/WB` and is forwarded like any ALU result, with no extra cycles. The next instruction reads the already updated CSR.

### 4.2. Write Rules

The file decides the operation from bits `[1:0]` of `funct3`.

| `funct3[1:0]` | Operation | New value |
| :---: | :--- | :--- |
| `01` | Write | $C' = S$ |
| `10` | Bit set | $C' = C \lor S$ |
| `11` | Bit clear | $C' = C \land \lnot S$ |

The source is considered null when the `rs1` field of the instruction is `x0` (in the immediate forms, `uimm = 0`). An instruction has write effect when it is a write (`CSRRW` and `CSRRWI`, even with `rd = x0`) or when the source is not null. With `rs1 = x0`, `CSRRS` and `CSRRC` read without writing and raise no exception on read-only CSRs, as the manual requires. The file always reads the CSR, including in `CSRRW` with `rd = x0`; since no Core CSR has a read side effect, the difference is not observable.

### 4.3. Illegal Access

The file flags an illegal access when the expression below holds.

$$\text{illegal} = \lnot\,\text{known\_address} \;\lor\; (\text{has\_write\_effect} \land \text{addr}[11{:}10] = 11)$$

An illegal access becomes an illegal-instruction exception (section 6). A write changes state only when the address is known, the CSR is not read-only and `commit` holds, and, for `mtvec`, `mscratch`, `mepc`, `mcause` and `mtval`, no trap, `MRET` or MEM-stage exception occurs in the same cycle.

## 5. CSR File

The addresses and names of the CSRs are not a choice of the Core. They come from the machine-level CSR table of the privileged architecture manual ([Currently allocated RISC-V machine-level CSR addresses](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-2-4-currently-allocated-risc-v-machine-level-csr-addresses)), and the convention of the address bits (read and write in bits [11:10], privilege in bits [9:8]) is in [section 1.1.1 of the same volume](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html#1-1-1-csr-address-mapping-conventions). The Access column follows the classes of the table, with R for `MRO` (read-only) and R/W for `MRW` (read and write), and the Definition column leads to the manual section that describes each register. The Core implements only a subset of the table.

All CSRs are zero after reset, except `misa` and the fixed part of `mstatus`, which are constants. The Write column describes the effect of an effective write.

| Address | CSR | Access | Definition | Read | Write |
| :---: | :--- | :---: | :---: | :--- | :--- |
| `0x300` | `mstatus` | R/W | [2.1.1.6](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-6-machine-status-mstatus-and-mstatush-registers) | `MPP` (bits 12 and 11) fixed at `11`, `MPIE` (bit 7), `MIE` (bit 3); other bits zero | Only `MIE` and `MPIE` are stored; other bits are ignored |
| `0x301` | `misa` | R/W | [2.1.1.1](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#misa) | `0x40000100` (`MXL = 1`, extension `I`); with `has_m`, `0x40001100` (adds bit 12, extension `M`); with `has_e` true (RV32E), bit 4 (extension `E`) replaces bit 8, and the value is `0x40000010` or, with `has_m`, `0x40001010` | Ignored |
| `0x304` | `mie` | R/W | [2.1.1.9](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-9-machine-interrupt-mip-and-mie-registers) | Zero; with `has_interrupts`, the masks `MSIE`, `MTIE` and `MEIE` (bits 3, 7 and 11) | With `has_interrupts`, writes bits 3, 7 and 11; the other bits are ignored |
| `0x305` | `mtvec` | R/W | [2.1.1.7](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#2-1-1-7-machine-trap-vector-base-address-mtvec-register) | `BASE` in bits `[31:2]` and `MODE` in bit 0 (`0` direct, `1` vectored); bit 1 reads zero. Without `has_interrupts`, `MODE` always reads zero | Stores `BASE` and, with `has_interrupts`, `MODE`; in vectored mode bits `[5:2]` of `BASE` are stored as zero (64-byte alignment) |
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

### 5.1. Machine Interrupts

The `has_interrupts` generic (default `false`, requires `has_zicsr`) turns on the three machine interrupt lines of the `core` and makes `mip` and `mie` work. The lines are level signals in the clock domain of the core; a source in another domain goes first through a `synchronizer` of `Common-Components`.

| Port | Interrupt | Bit in `mip` and `mie` |
| :--- | :--- | :---: |
| `i_irq_software` | Machine software (`MSIP`, `MSIE`) | 3 |
| `i_irq_timer` | Machine timer (`MTIP`, `MTIE`) | 7 |
| `i_irq_external` | Machine external (`MEIP`, `MEIE`) | 11 |

The `mip` register is read-only and reads the current level of the three lines at bits 3, 7 and 11; the other bits read zero. A write to `mip` is legal and changes nothing. The `mie` register holds bits 3, 7 and 11; the other bits read zero and ignore the write, and the value after reset is zero. A write to `mie` follows the general rules of section 4.2 and does not happen in the cycle of a trap or an `MRET`.

The `csr_file` delivers the interrupt decision on three outputs. `o_irq_pending` tells that an interrupt is pending and enabled in `mie`, regardless of `mstatus.MIE`, and `o_irq_take` adds `mstatus.MIE`. `o_irq_cause` carries the `mcause` of the highest-priority interrupt among those pending and enabled.

$$\text{o\_irq\_pending} = \left(\text{mip} \land \text{mie}\right) \ne 0 \qquad \text{o\_irq\_take} = \text{mstatus.MIE} \land \text{o\_irq\_pending}$$

| Pending and enabled | `o_irq_cause` |
| :--- | :---: |
| External (`MEIP` and `MEIE`) | `0x8000000B` |
| Software (`MSIP` and `MSIE`), without external | `0x80000003` |
| Timer (`MTIP` and `MTIE`), without the two above | `0x80000007` |
| Counter overflow (`LCOFIP` and `LCOFIE`, Sscofpmf only), without the three above | `0x8000000D` |

The counter-overflow interrupt belongs to the [Sscofpmf](../Sscofpmf/description.md) extension, which adds bit 13 to `mip` and `mie`.
With `has_interrupts = false`, the ports are ignored, `mie` and `mip` read zero and ignore writes, `o_irq_pending` and `o_irq_take` are `0` and the `MODE` of `mtvec` reads zero. The bit positions and the `mcause` code of each interrupt are in the `irq_consts` package.

## 6. Synchronous Exceptions

### 6.1. Generated Causes

`trap_unit` evaluates the instruction in the EX stage and flags at most one exception per instruction, only when the instruction is valid and the pipeline advances.

| `mcause` | Exception | Condition | `mtval` |
| :---: | :--- | :--- | :--- |
| 0 | Instruction address misaligned | Taken branch, `JAL` or `JALR` with target bits `[1:0]` different from `00` | Target address |
| 2 | Illegal instruction | Undefined encoding flagged by the ID-stage decoder, unsupported `SYSTEM` instruction, or illegal CSR access (section 4.3) | Zero |
| 3 | Breakpoint | `EBREAK` (`funct12 = 0x001`) | Zero |
| 1 | Instruction access fault | Instruction fetch outside the executable regions of the map, with `has_access_faults` (section 6.7) | Instruction PC |
| 4 | Load address misaligned | Misaligned load that the hardware does not execute | Effective address |
| 5 | Load access fault | Load to an address the map does not accept for reading, with `has_access_faults` (section 6.7) | Effective address |
| 6 | Store address misaligned | Misaligned store that the hardware does not execute | Effective address |
| 7 | Store access fault | Store to an address the map does not accept for writing, with `has_access_faults` (section 6.7) | Effective address |
| 11 | Machine-mode environment call | `ECALL` (`funct12 = 0x000`) | Zero |

The `ECALL`, `EBREAK`, `MRET` and `WFI` instructions are recognized only with `funct3 = 000`, `rd = x0` and `rs1 = x0`. Any other non-CSR `SYSTEM` instruction, including `funct3 = 100`, `SRET` and `SFENCE.VMA`, is illegal. The ID-stage decoder also flags as illegal a register index above 15 when the profile is RV32E.

A load or store misalignment is defined by the rules of the `Zicclsm` extension: the hardware executes the misaligned access inside main memory (internal RAM and SDRAM) when `has_zicclsm = true`, and any other misalignment raises causes 4 and 6. With `has_zicsr = true`, these two causes are checked in the MEM stage by a second `trap_unit` instance, which reads the effective address already registered in `EX/MEM`, and the EX-stage instance does not check the effective address.

### 6.2. Priority

For the EX-stage instance, the priority is the one in the table, from top to bottom.

| Priority | `mcause` |
| :---: | :---: |
| 1 | 1 (fetch fault, with `has_access_faults`) |
| 2 | 2 |
| 3 | 0 |
| 4 | 3 |
| 5 | 11 |

The order is the one of Table 17 of the privileged volume: the illegal instruction comes before the misaligned instruction address. A `JALR` or a branch with a reserved encoding and a misaligned target raises cause 2 with `mtval` zero, and only the legal jump raises cause 0.

The load or store exception (causes 4, 5, 6 and 7) belongs to an instruction older than the one in the EX stage and therefore has priority over all EX causes. When it occurs, the EX instruction is discarded entirely, with no CSR write, branch, `MRET`, `FENCE.I` or retirement.

### 6.3. Handler Entry

When an exception is taken, the CSR file performs the following actions in the same cycle.

1. `mepc` receives the PC of the faulting instruction, with the two low bits cleared.
2. `mcause` receives the cause code and `mtval` receives the associated value.
3. `mstatus.MPIE` receives `mstatus.MIE`, and `mstatus.MIE` goes to zero.
4. The PC takes the value of `mtvec`.

If the exception occurs in the MEM stage, the PC saved in `mepc` is that of the load or store instruction, carried in `EX/MEM`.

### 6.4. Return with MRET

The `MRET` instruction (`funct12 = 0x302`) is detected in EX. It restores `mstatus.MIE` with the value of `mstatus.MPIE`, sets `mstatus.MPIE` to `1` and redirects the PC to `mepc`. The `WFI` instruction (`funct12 = 0x105`) is accepted as a legal instruction and executes as a `NOP` (section 7.6).

### 6.5. Redirection and Flush

The redirect PC is chosen among `mepc` (on `MRET`), `PC + 4` (on `FENCE.I`), the `mtvec` vector (on an interrupt with vectored `mtvec`, section 7.5) and the `BASE` of `mtvec` (in the other cases). The PC selector gives redirection the highest priority over branches and `JALR`, and the PC register accepts the new value even with the pipeline frozen.

| Event | Registers flushed | Note |
| :--- | :--- | :--- |
| Exception or interrupt in EX | `IF/ID`, `ID/EX`, `EX/MEM` | The faulting or aborted instruction neither writes `rd` nor accesses memory |
| Exception in MEM | `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` | The faulting access does not reach memory and the EX instruction is discarded |
| `MRET` | `IF/ID`, `ID/EX` | `MRET` itself continues in the pipeline as an instruction with no register effect |

### 6.6. Latency

The EX exception is detected combinationally in the cycle in which the instruction is in EX and the pipeline advances. The CSRs and the PC are written at the clock edge that ends that cycle, so the first handler instruction is fetched in the following cycle. Two younger instructions (in the IF and ID stages) are discarded, besides the faulting instruction itself. The load or store exception is detected in the cycle in which the access reaches MEM, one cycle after the instruction passed through EX.

The retirement of an instruction in EX adds to `minstret` one cycle later, and a MEM exception cancels that addition, so the failing access does not count as retired. Counter details are in [Zicntr](../Zicntr/description.md) and [Zihpm](../Zihpm/description.md).

### 6.7. Access Faults

The `has_access_faults` generic (default `false`, needs `has_zicsr`) turns on causes 1, 5 and 7. The valid map comes from the same memory-map generics the Core already receives (`rom_end_kib`, `ram_base_kib`, `ram_end_kib`, `ext_base_kib` and `periph_base_kib`) and from the `periph_slots` generic, the mask of the 256 MiB windows of the peripheral bus that hold a peripheral (bit $n$ for the addresses whose bits 30:28 equal $n$), which `riscv-tools` writes to the map package as `PERIPH_SLOTS`. The extension is turned on by `extras: [AccessFaults]` in `platform.yaml`.

| Region | Read | Write | Fetch |
| :--- | :---: | :---: | :---: |
| ROM, from zero to `rom_end_kib` (BOOT_MEMORY and FLASH) | Yes | No | Yes |
| RAM, from `ram_base_kib` to `ram_end_kib` | Yes | Yes | Yes |
| External window, from `ext_base_kib` to `periph_base_kib` | Yes | Yes | Yes |
| Occupied peripheral window, from `periph_base_kib` up | Yes | Yes | No |
| The rest (gaps between regions, empty peripheral windows) | No | No | No |

The read and write validity of the effective address is decided in the EX stage, from the ALU result, next to the address classification that `reg_ex_mem` already registers, and the MEM stage only checks the registered bit. The fetch validity comes from the PC of the instruction in EX, from a register, off the ALU path. With `has_access_faults = false` the validities are always `1` and none of this is synthesized.

The fetch fault goes before the illegal instruction, and the data one before the misalignment, in the order of Table 17 of the privileged volume. A load or store fault belongs to the address of the first word, and the access does not reach the memories, as with misalignment.

## 7. Interrupt Entry

### 7.1. Condition

The `trap_unit` takes the interrupt that the `csr_file` reports on `o_irq_take` on the instruction in EX. The interrupt is taken only with a valid instruction in EX and the pipeline advancing, and never on `FENCE.I`.

$$\text{take} = \text{mstatus.MIE} \land \left( (\text{mip} \land \text{mie}) \ne 0 \right) \land \text{valid} \land \text{pipe\_run} \land \lnot\,\text{FENCE.I}$$

While the condition does not hold, the interrupt stays pending and the program goes on. The line is level-sensitive, so it is taken as soon as the condition holds, and the handler must acknowledge it in the peripheral before returning.

### 7.2. Priority

| Order | Event | `mcause` |
| :---: | :--- | :---: |
| 1 | Machine external interrupt | `0x8000000B` |
| 2 | Machine software interrupt | `0x80000003` |
| 3 | Machine timer interrupt | `0x80000007` |
| 4 | Counter-overflow interrupt (Sscofpmf) | `0x8000000D` |
| 5 | Synchronous exception of the instruction in EX (section 6.2) | Exception code |

The interrupt has priority over the synchronous exception and over the `MRET` of the instruction in EX: it is aborted and becomes the return instruction, and the exception only happens if the instruction runs after the return. The load or store exception of the MEM stage belongs to an older instruction and wins over the interrupt: the exception discards the EX instruction, and the interrupt stays pending until the handler gives control back.

### 7.3. Entry Point

| Rule | Effect |
| :--- | :--- |
| `mepc` receives the PC of the instruction in EX | It is the first instruction that did not complete, and the return by `MRET` runs it. The FreeRTOS port does not add 4 to `mepc` on an interrupt |
| Older instructions complete | Those in MEM and WB finish normally |
| The instruction in EX and the newer ones are discarded | `IF/ID`, `ID/EX` and `EX/MEM` are flushed; no register write, store, CSR write or `FENCE.I` of these instructions becomes visible |
| `mcause` receives the interrupt code, with bit 31 at `1` | `mtval` receives zero |
| `mstatus.MPIE` receives `mstatus.MIE`, and `mstatus.MIE` goes to zero | Same as the synchronous exception |
| The aborted instruction does not count in `minstret` | It counts when it runs after the return |

An aborted CSR access writes nothing: `mtvec`, `mscratch`, `mie`, the counters and `mstatus` stay as they were, except for the effect of the entry itself on `mstatus`, `mepc`, `mcause` and `mtval`.

### 7.4. Cases that Defer the Entry

The entry waits while the pipeline does not advance or there is no valid instruction in EX. None of these cases splits an instruction in the middle.

| Situation in progress | Effect |
| :--- | :--- |
| Multiplication or division | The pipeline stays stopped until the end. In the cycle the result is ready the interrupt aborts the instruction, which redoes the computation after the return |
| Misaligned access in two steps | Both steps finish before the entry |
| SDRAM read or write wait | The access finishes before the entry |
| Fetch waiting for `i_ic_ready` | There is no valid instruction in EX; the interrupt is taken on the first valid instruction that arrives |
| Bubble in EX (taken jump, load dependency) | The interrupt is taken on the first valid instruction that arrives |
| `FENCE.I` in EX | The instruction redirects the pipeline to the next one and completes; the interrupt is taken on that next instruction |

A line that rises again before the first program instruction retires repeats the same entry forever. The interval between interrupts must therefore exceed the handler duration plus that of the longest program instruction, which is the division.

### 7.5. `mtvec` Modes

| `MODE` (bit 0) | Destination of an interrupt | Destination of a synchronous exception |
| :---: | :--- | :--- |
| `0` (direct) | `BASE` | `BASE` |
| `1` (vectored) | $\text{BASE} + 4 \times \text{cause}$ | `BASE` |

Modes `2` and `3` are reserved, and bit 1 reads zero. In vectored mode `BASE` has 64-byte alignment, because the largest implemented interrupt cause is 11 and the table has 16 entries of 4 bytes. With that alignment the sum is the replacement of bits `[5:2]` of `BASE` by the four low bits of the cause, with no adder. `ECALL` has cause 11 and goes to `BASE`, because the vector applies to interrupts only.

| Cause | Table position |
| :---: | :---: |
| 3 (software) | `BASE + 12` |
| 7 (timer) | `BASE + 28` |
| 11 (external) | `BASE + 44` |

### 7.6. MRET and WFI

`MRET` follows section 6.4. `WFI` executes as a `NOP`, as the privileged manual allows, so the core does not stop waiting for an interrupt. An interrupt taken on `WFI` gives control back to the `WFI` itself, which executes as a `NOP` on return.

## 8. Core without Zicsr

With `has_zicsr = false`, `csr_file` and `csr_decode` are not instantiated and there are no trap registers. The Core keeps a cause detector that only flags the exception on its outputs and does not redirect the PC.

| Output | Value |
| :--- | :--- |
| `o_trap` | One-cycle pulse at `1` when an exception occurs; stays at `0` with Zicsr |
| `o_trap_cause` | Cause code in the `mcause` format; stays at zero with Zicsr |
| `o_trap_pc` | PC of the instruction that raised the exception; stays at zero with Zicsr |
| `o_trap_take` | One-cycle pulse at `1` when the Core takes a synchronous exception, with or without Zicsr |

In this mode, every CSR access instruction is illegal (cause 2), `ECALL` raises cause 11 and `EBREAK` cause 3, and load and store misalignment (causes 4 and 6) is checked in the EX stage itself. Branch target misalignment is not checked, and `MRET` has no effect. The faulting instruction is annulled in EX, with no `rd` write and no memory access, and the program continues at the next instruction. The instruction that raised the exception does not count as retired. The environment around the Core decides what to do with the signal.

The `o_trap_take` output exists in both modes. With Zicsr, it pulses in the cycle in which the Core redirects the PC to `mtvec`, when `o_trap` stays at `0`, and it is the signal a synthesis top uses to show the exception, for example on an LED. Without Zicsr, it pulses together with `o_trap`. A machine interrupt, when taken, must also pulse `o_trap_take`.

A core with neither `Zicsr` nor `Zicclsm` is valid: the misaligned access is only signalled on `o_trap`. `Zicntr` and `Zihpm` require `Zicsr`, and elaboration fails without it.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
