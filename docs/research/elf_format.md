# ELF Format

## What is ELF?

**ELF** stands for **Executable and Linkable Format**. It's the standard binary
file format used on Linux, Unix-like systems, and many embedded systems for:

- **Executables** - Programs you can run directly
- **Object files** - Compiled code that hasn't been linked yet (`.o` files)
- **Shared libraries** - `.so` files (shared objects)
- **Core dumps** - Memory snapshots for debugging

## Why ELF?

ELF was designed to replace older formats (like `a.out`) because it:

1. **Supports multiple architectures** - ARM64, x86-64, RISC-V, etc.
2. **Flexible structure** - Can represent executables, libraries, and object
   files
3. **Efficient loading** - The OS can load programs into memory efficiently
4. **Standardized** - Defined by the System V ABI specification

## ELF Variants

- **ELF32** - 32-bit addresses and offsets (older systems)
- **ELF64** - 64-bit addresses and offsets (modern systems, including ARM64)

Your project uses **ELF64** (as specified in `README.md`: "Binary format: ELF64
for Linux").

## ELF File Structure

An ELF file consists of several key parts:

### 1. ELF Header

Located at the start of the file, contains:

- **Magic number** - Identifies the file as ELF (`0x7F 'E' 'L' 'F'`)
- **Architecture** - 32-bit or 64-bit
- **Endianness** - Byte order (little-endian or big-endian)
- **Machine type** - CPU architecture (e.g., ARM64/AArch64)
- **Entry point** - Memory address where execution begins (`_start`)
- **Program header table** - Location and size
- **Section header table** - Location and size

### 2. Program Header Table

Describes **segments** - how the file should be loaded into memory:

- **Loadable segments** - Code and data that get loaded into memory
- **Dynamic linking info** - Information for shared libraries
- **Interpreter** - Program loader (e.g., `/lib/ld-linux-aarch64.so.1`)

### 3. Sections

Contain the actual code and data:

- **`.text`** - Executable code (your assembly instructions)
- **`.data`** - Initialized data (your string constants)
- **`.bss`** - Uninitialized data (zero-initialized variables)
- **`.rodata`** - Read-only data
- **`.symtab`** - Symbol table (function/variable names)
- **`.strtab`** - String table (names referenced by symbol table)

### 4. Section Header Table

Metadata about each section - where it is, its size, permissions, etc.

## How Your Assembly Becomes an ELF File

When you compile `src/hello.s`:

```bash
clang --target=aarch64-linux-gnu -c src/hello.s -o hello.o
```

This creates an **object file** (`.o`) - an ELF file containing:

- Your code in `.text` section
- Your data (`msg`) in `.data` section
- Symbol information (`_start`, `msg`, `msg_end`)

When you link it:

```bash
ld.lld hello.o -o hello
```

The linker:

1. Reads the object file(s)
2. Resolves symbols (finds `_start`)
3. Combines sections
4. Sets the entry point to `_start`
5. Creates the final ELF executable

## Inspecting ELF Files

You can examine ELF files using various tools:

### `file` command

```bash
file hello
# Output: hello: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, ...
```

### `readelf` command

```bash
readelf -h hello          # Show ELF header
readelf -l hello          # Show program headers (segments)
readelf -S hello          # Show section headers
readelf -s hello          # Show symbol table
```

### `objdump` command

```bash
objdump -d hello          # Disassemble code sections
objdump -s hello          # Show all sections
```

### `hexdump` or `xxd`

```bash
xxd hello | head          # View raw bytes (you'll see "7f 45 4c 46" = ELF magic)
```

## ELF in Your Project

In Drift:

1. **Source** - `src/hello.s` (assembly source)
2. **Object file** - `hello.o` (ELF object file after `clang -c`)
3. **Executable** - `hello` (ELF executable after linking)

The final binary is an ELF64 executable for ARM64 Linux, which:

- Can be executed directly on ARM64 Linux systems
- Contains your assembly code in the `.text` section
- Has `_start` as its entry point
- Can be packaged in a Docker container and run

## Key Takeaways

- **ELF is the container** - It's the file format that wraps your code
- **Sections organize content** - `.text` for code, `.data` for data
- **Header tells the OS how to load it** - Entry point, architecture, etc.
- **Standard across Linux** - All Linux executables use ELF (with rare
  exceptions)

Understanding ELF helps you understand:

- How your assembly becomes a runnable program
- What the linker does
- How the OS loads and executes your program
- Why certain conventions (like `_start`) exist
