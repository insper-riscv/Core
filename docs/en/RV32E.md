# 16-Register File (RV32E)

The `num_regs` generic of the `core` chooses how many general-purpose registers the processor has. With 32, the default, it is an RV32I. With 16, it is an RV32E, which gives up registers `x16` to `x31` for less area.

## 1. What Changes

| Item | `num_regs = 32` | `num_regs = 16` |
| :--- | :--- | :--- |
| Registers | `x0` to `x31` | `x0` to `x15` |
| `reg_file` address | 5 bits | 4 bits |
| Instruction using `x16` to `x31` | Runs | Illegal, `mcause` 2 with `has_zicsr` |

Only the values 16 and 32 are accepted, and any other value fails the elaboration.

## 2. Illegal Instruction

In the RV32E the top bit of every register field the instruction uses must be zero. The ID stage checks the three fields by the shape of the instruction.

| Field | Instructions that use it |
| :--- | :--- |
| `rd` | LUI, AUIPC, JAL, JALR, loads, immediate operations, register-register operations and CSR instructions |
| `rs1` | JALR, branches, loads, stores, immediate operations, register-register operations and CSR with a register |
| `rs2` | Branches, stores and register-register operations |

An illegal instruction writes no register and takes the same exception path as any other illegal instruction. Fields the instruction does not use, such as the `rs2` of a load, are not checked.

## 3. Compatibility

The smaller file changes neither the pipeline nor the forwarding, which keep comparing 5-bit indices. RV32E programs use the `ilp32e` ABI, which allocates registers only up to `x15`.
