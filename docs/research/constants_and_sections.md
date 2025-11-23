# Constants and Sections

## Constants Don't Have to Be in `.data`

Constants can be placed in different sections depending on their type and usage.
There are actually **three main ways** to handle constants in assembly:

## 1. Compile-Time Constants (Symbol Assignments)

These **don't go in any section** and it's typical to place them either at the
top of the file or close to where they are used - they're compile-time symbol
substitutions.

### `.equ` directive

```assembly
.equ STDOUT_FILENO, 1
.equ STDIN_FILENO, 0
.equ BUFFER_SIZE, 1024
```

### `=` operator (Symbol Assignment)

```assembly
msg_len = . - msg        # Calculated value
buffer_size = 1024       # Simple assignment
```

**What are symbol assignments?**

Both `.equ` and `=` create **symbol assignments** (also called assembly-time
constants). They create a symbol and assign it a value that's computed at
assembly time, not runtime.

**Characteristics:**

- **No memory allocated** - The assembler replaces the symbol with its value
- **Computed at assembly time** - Expressions are evaluated during assembly
- **Can be used anywhere** - In instructions, calculations, etc.
- **Similar to `#define` in C** - Text substitution, not data storage
- Example: `mov x0, #STDOUT_FILENO` becomes `mov x0, #1` after assembly

**Difference between `.equ` and `=`:**

- `.equ` - Defines a constant that cannot be reassigned
- `=` - Creates a symbol that can be reassigned (though you typically don't)

Both are functionally equivalent for most use cases. Use whichever feels more
natural - `.equ` is more explicit about being a constant, while `=` is more
concise.

## 2. Read-Only Data Constants (`.rodata` section)

For **read-only data** like string literals, use the **`.rodata`** section:

```assembly
.section .rodata

msg:
    .ascii "Hello from Drift on ARM64!\n"
msg_end:

error_msg:
    .ascii "Error occurred\n"
```

**Characteristics:**

- Memory is allocated (the string exists in the binary)
- Marked as read-only by the OS (prevents accidental modification)
- More efficient - can be shared between processes
- **Better security** - OS will prevent writes (segmentation fault if you try)

## 3. Writable Data (`.data` section)

For **mutable initialized data**, use `.data`:

```assembly
.section .data

counter:
    .quad 0          # A variable that can be modified
buffer:
    .space 256        # Uninitialized space for a buffer
```

**Characteristics:**

- Memory is allocated
- Can be read and written
- Use only when you need to modify the data

## Section Summary

| Section   | Purpose            | Writable?       | Use For                                  |
| --------- | ------------------ | --------------- | ---------------------------------------- |
| `.text`   | Executable code    | No (executable) | Your assembly instructions               |
| `.rodata` | Read-only data     | No              | String literals, constants               |
| `.data`   | Initialized data   | Yes             | Variables that need initial values       |
| `.bss`    | Uninitialized data | Yes             | Zero-initialized variables (saves space) |

## Embedded Constants in Instructions

You can also embed small constants directly in instructions:

```assembly
mov x0, #1           # Immediate value (1) embedded in instruction
mov x0, #0x42        # Hexadecimal constant
mov x0, #'A'         # Character constant (ASCII 65)
```

These don't require any section - they're part of the instruction encoding
itself.

## Best Practices

1. **Use `.equ` for numeric constants** - File descriptors, sizes, flags, etc.
   ```assembly
   .equ STDOUT_FILENO, 1
   .equ MAX_BUFFER, 4096
   ```

2. **Use `.rodata` for read-only data** - Strings, lookup tables, etc.
   ```assembly
   .section .rodata
   msg: .ascii "Hello\n"
   ```

3. **Use `.data` only when you need writable data**
   ```assembly
   .section .data
   counter: .quad 0
   ```

4. **Use `.bss` for zero-initialized variables** (saves space in binary)
   ```assembly
   .section .bss
   buffer: .space 1024
   ```

## Why `.rodata` Matters

- **Security** - Prevents accidental modification (segfault if you try)
- **Efficiency** - Can be shared between multiple instances of the program
- **Clarity** - Makes it clear the data is read-only
- **Optimization** - Compiler/linker can optimize better

## Example: Proper Constant Usage

```assembly
# Compile-time constants (no section needed)
.equ STDOUT_FILENO, 1
.equ EXIT_SUCCESS, 0

# Read-only data constants
.section .rodata
hello_msg:
    .ascii "Hello, World!\n"
hello_len = . - hello_msg

# Writable data (only if needed)
.section .data
write_count:
    .quad 0

# Code
.section .text
.global _start

_start:
    mov x0, #STDOUT_FILENO    # Use .equ constant
    adr x1, hello_msg          # Reference .rodata constant
    mov x2, #hello_len         # Use symbol assignment constant
    mov x8, #64
    svc #0

    mov x0, #EXIT_SUCCESS
    mov x8, #93
    svc #0
```
