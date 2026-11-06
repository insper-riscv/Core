# 16-Register File (RV32E)

The boolean `has_e` generic of the `core` chooses how many general-purpose registers the processor has. False, the default, gives an RV32I with 32 registers. True gives an RV32E, which gives up registers `x16` to `x31` for less area. The manual requirements are in [instructions.md](instructions.md).

## 1. Reference

| Item | Value |
| :--- | :--- |
| Chapter | 2, RV32E and RV64E Base Integer Instruction Sets, version 2.0 |
| Source | Volume I of the RISC-V manual (unprivileged ISA, version 20260120), numbered without the Introduction |
| Manual requirements | [instructions.md](instructions.md) |

## 2. What Changes

| Item | `has_e = false` | `has_e = true` |
| :--- | :--- | :--- |
| Registers | `x0` to `x31` | `x0` to `x15` |
| `reg_file` address | 5 bits | 4 bits |
| Instruction using `x16` to `x31` | Runs | Illegal, `mcause` 2 with `has_zicsr` |
| Base bit of `misa` with `has_zicsr` | `I` (bit 8) | `E` (bit 4), and the `I` bit is zero |

The `misa` follows the privileged manual ([section 2.1.1.1](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html#misa)), which sets the `E` bit in the RV32E and defines it as reading as the complement of the `I` bit. The ID stage computes the register file address width (5 bits with `has_e` false, 4 bits with `has_e` true) and wires only those low bits of the `rs1`, `rs2` and `rd` indices to the file.

## 3. Illegal Instruction

The manual reserves the encodings with `x16` to `x31` (section 2.1.2), and the Core treats them as an illegal instruction. In the RV32E the top bit of every register field the instruction uses must be zero. The ID stage checks the three fields by the shape of the instruction.

| Field | Instructions that use it |
| :--- | :--- |
| `rd` | LUI, AUIPC, JAL, JALR, loads, immediate operations, register-register operations and CSR instructions |
| `rs1` | JALR, branches, loads, stores, immediate operations, register-register operations and CSR with a register |
| `rs2` | Branches, stores and register-register operations |

An illegal instruction writes no register and takes the same exception path as any other illegal instruction. Fields the instruction does not use, such as the `rs2` of a load, are not checked.

### 3.1. Exception Destination

| Configuration | Effect |
| :--- | :--- |
| With `has_zicsr` | Synchronous trap with cause 2 (illegal instruction) recorded in `mcause` |
| Without `has_zicsr` | One-cycle pulse on the trap output of the `core`, with the cause in the `mcause` format and the PC of the instruction |

## 4. Compatibility

The smaller file changes neither the pipeline nor the forwarding, which keep comparing 5-bit indices. Since the illegal-instruction check depends only on `has_e`, it is independent of the other extensions, and the 60 extension combinations of `profiles/matrix.yaml` hold for both the 32-register base and the 16-register one, which gives 120 profiles.

RV32E programs use the `ilp32e` ABI, defined in the [RISC-V psABI](https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/v1.0/riscv-cc.adoc#ilp32e-calling-convention) (outside the ISA manual), which allocates registers only up to `x15`.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
