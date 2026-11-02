# Zicsr: Extension Instructions

Chapter 5 of the manual ([Zicsr Extension for Control and Status Register (CSR) Instructions](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)).

This document summarizes what the RISC-V manual requires of the `Zicsr` extension (instructions that access control and status registers, CSRs). The reference is the unprivileged ISA manual v20260120, Chapter 5, "Zicsr" Extension for Control and Status Register (CSR) Instructions, Version 2.0, section 5.1 and its subsections. The Core implementation is in [description.md](description.md).

## 1. Extension Scope

Each hart has its own CSR address space of 4096 registers (manual, section 5.1). The extension's instructions are the only ones that explicitly access that space. Counters and timers are no longer mandatory in the base ISA, and their access instructions moved from RV32I to this chapter.

## 2. Instructions

### 2.1. Format and Encoding

The six instructions use the `SYSTEM` opcode (`1110011`). The `csr` field occupies bits 31 to 20, and the immediate forms hold a zero-extended 5-bit value in the `rs1` field (manual, section 5.1.1). The full encoding is in the instruction listing of Chapter 35, "RV32/64G Instruction Set Listings".

| Instruction | Bits 31 to 20 | Bits 19 to 15 | Bits 14 to 12 (`funct3`) | Bits 11 to 7 | Bits 6 to 0 |
| :--- | :--- | :--- | :---: | :--- | :--- |
| `CSRRW` | `csr` | `rs1` | `001` | `rd` | `1110011` |
| `CSRRS` | `csr` | `rs1` | `010` | `rd` | `1110011` |
| `CSRRC` | `csr` | `rs1` | `011` | `rd` | `1110011` |
| `CSRRWI` | `csr` | `uimm[4:0]` | `101` | `rd` | `1110011` |
| `CSRRSI` | `csr` | `uimm[4:0]` | `110` | `rd` | `1110011` |
| `CSRRCI` | `csr` | `uimm[4:0]` | `111` | `rd` | `1110011` |

### 2.2. Semantics

Each instruction atomically reads and modifies a single CSR. Let $C$ be the old CSR value, $S$ the source operand (the value of `rs1` in the register forms and `uimm` in the immediate forms) and $C'$ the new value.

| Instruction | Value written to `rd` | New CSR value |
| :--- | :--- | :--- |
| `CSRRW`, `CSRRWI` | $C$ zero-extended to `XLEN` | $C' = S$ |
| `CSRRS`, `CSRRSI` | $C$ | $C' = C \lor S$ (each 1 bit of $S$ sets the matching bit, if it is writable) |
| `CSRRC`, `CSRRCI` | $C$ | $C' = C \land \lnot S$ (each 1 bit of $S$ clears the matching bit, if it is writable) |

A bit that reads a different value from the one it stores can change in a `CSRRS` or `CSRRC` even when $S$ does not select it (the manual gives a `pmpaddr` bit as an example).

### 2.3. Conditional Reads and Writes

The registers used as `rd`, `rs1` or `uimm` decide whether the instruction reads and whether it writes the CSR (manual, Table 1 of section 5.1.1).

| Instruction | Condition | Reads the CSR | Writes the CSR |
| :--- | :--- | :---: | :---: |
| `CSRRW` | `rd = x0` | No | Yes |
| `CSRRW` | `rd ≠ x0` | Yes | Yes |
| `CSRRS`, `CSRRC` | `rs1 = x0` | Yes | No |
| `CSRRS`, `CSRRC` | `rs1 ≠ x0` | Yes | Yes |
| `CSRRWI` | `rd = x0` | No | Yes |
| `CSRRWI` | `rd ≠ x0` | Yes | Yes |
| `CSRRSI`, `CSRRCI` | `uimm = 0` | Yes | No |
| `CSRRSI`, `CSRRCI` | `uimm ≠ 0` | Yes | Yes |

Additional manual rules:

- `CSRRS` and `CSRRC` with `rs1 = x0`, as well as `CSRRSI` and `CSRRCI` with `uimm = 0`, do not write the CSR. They produce no write side effects and raise no illegal-instruction exception on read-only CSRs.
- `CSRRS` and `CSRRC` always read the CSR and trigger read side effects, whatever `rd` and `rs1` are.
- If `rs1` is not `x0` but holds zero, there are no per-field side effects, and the side effects of writing the whole CSR still apply.
- `CSRRW` with `rs1 = x0` writes zero to the CSR.

### 2.4. Atomicity and Side Effects

The read and the write of one instruction form a single indivisible operation on the CSR. Write side effects follow the rule below (manual, section 5.1.1).

| Operation | Fields that suffer write side effects |
| :--- | :--- |
| `CSRRW`, `CSRRWI` | All fields of the written CSR |
| `CSRRS`, `CSRRSI`, `CSRRC`, `CSRRCI` | Only the fields that have some 1 bit in `rs1` or `uimm` |

Standard CSRs have no read side effects and, as of the manual's date, none has per-field side effects, so the effect of an access to a standard CSR follows from the opcode alone. Defining CSRs with per-field side effects is discouraged. Consequences that occur only because the CSR now holds a certain value, such as a trap caused by the new state, are indirect effects and not side effects.

For a counter that the hardware updates during execution (for example `instret`), the explicit read returns the value from before the instruction, the explicit write replaces the hardware update for that instruction, and the written value is what the next instruction reads.

### 2.5. Pseudoinstructions

| Pseudoinstruction | Expansion |
| :--- | :--- |
| `CSRR rd, csr` | `CSRRS rd, csr, x0` |
| `CSRW csr, rs1` | `CSRRW x0, csr, rs1` |
| `CSRWI csr, uimm` | `CSRRWI x0, csr, uimm` |

The manual also defines `CSRS`, `CSRC`, `CSRSI` and `CSRCI` for the cases where the old value is not needed.

### 2.6. Access Ordering

According to manual section 5.1.1.1, "CSR Access Ordering":

- A hart observes its own CSR accesses in program order, including implicit ones. The explicit read returns the state from before the instruction, the explicit write suppresses and overrides implicit writes by the same instruction, and the next instruction already sees all consequences.
- Under the memory model (RVWMO), CSR accesses are weakly ordered with respect to other harts and devices, and are not ordered with respect to explicit memory accesses, except through syntactic dependencies, platform memory-ordering attribute rules, or an effect on the execution of the memory access.
- Software enforces other orderings with `FENCE`. For that purpose, a CSR read counts as device input (`I`) and a CSR write as device output (`O`).
- A platform may declare certain CSRs strongly ordered.

## 3. CSR Address Space

The unprivileged manual fixes only the 12-bit field (4096 addresses). The access conventions come from the privileged architecture manual, Chapter 1, section 1.1.1, "CSR Address Mapping Conventions".

| Address bits | Meaning |
| :--- | :--- |
| `[11:10]` | Access type; `00`, `01` and `10` mean read/write, and `11` means read-only |
| `[9:8]` | Lowest privilege level that can access the CSR (`00` user, `01` supervisor, `11` machine; the pattern `10` appears in the hypervisor CSRs) |

The effects of a violation, according to the same manual, are the following.

| Situation | Result |
| :--- | :--- |
| Write to a read-only CSR | Illegal-instruction exception |
| Insufficient privilege | Illegal-instruction exception (or virtual-instruction exception in the hypervisor cases) |
| Nonexistent CSR | The instruction is reserved; the text consulted does not name the exception |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../../LICENSE).
