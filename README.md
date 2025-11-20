# Drift

HTTP Server built in ARM64 Linux Assembly.

```text
Architecture    : ARM64 / AArch64 (ARMv8-A)
Instruction set : A64
Assembler       : LLVM integrated assembler (via clang)
Syntax          : GAS-compatible (GNU Assembler / AT&T-style ARM64 syntax)
ABI             : AArch64 Linux SysV ABI
Binary format   : ELF64 for Linux
Syscall method  : AArch64 Linux syscall table using svc #0
```

## Setup

Install dependencies:

```bash
mise install
```

## Formatting

Format repository files:

```bash
mise run format
```

Or directly:

```bash
dprint fmt
```
