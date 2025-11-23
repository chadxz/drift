# Entry Point

## Canonical Name: `_start`

The canonical name for the entry point in assembly programs (and low-level
programs without a C runtime) is **`_start`**.

### Why `_start`?

1. **Linker default** - The linker (`ld` or `ld.lld`) looks for a symbol named
   `_start` by default as the entry point of the program. This is specified in
   the ELF (Executable and Linkable Format) standard.

2. **No C Runtime** - When writing pure assembly (no CRT/libc), `_start` is
   where execution begins. The operating system's program loader transfers
   control directly to this symbol.

3. **Convention** - This is the standard convention across Unix-like systems
   (Linux, BSD, macOS, etc.) for programs that don't use a C runtime.

### Declaration in Assembly

In GAS/AT&T-style ARM64 assembly, you declare it like this:

```assembly
.section .text
.global _start

_start:
    # Your program code starts here
```

- `.global _start` - Makes the symbol visible to the linker (exports it)
- `_start:` - Defines the label where execution begins

### How It Works

1. **Program loader** - When you execute a program, the OS loader reads the ELF
   file and looks for the entry point address
2. **Entry point** - The linker sets the entry point to the address of `_start`
   (unless overridden)
3. **Execution begins** - The CPU starts executing instructions at `_start`

### Custom Entry Points

You can override the default entry point using linker flags:

```bash
ld -e my_custom_entry_point ...
```

However, **`_start` is the standard and expected name** - using anything else
requires explicit linker configuration and is non-standard.

### Comparison with C Programs

In C programs:

- The **C Runtime (CRT)** provides its own `_start` function
- CRT's `_start` sets up the environment, calls `main()`, and handles cleanup
- Your `main()` function is called by the CRT, not directly by the OS

In pure assembly:

- You define `_start` yourself
- Execution starts directly at `_start` (no CRT)
- You're responsible for all initialization and cleanup

### Best Practice

**Always use `_start` as your entry point name** in assembly programs. This
ensures:

- Compatibility with standard linkers
- No need for custom linker flags
- Consistency with Unix/Linux conventions
- Predictable behavior across toolchains
