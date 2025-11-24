# Using Radare2 (r2) with ARM64 Assembly

Radare2 (r2) is a powerful reverse engineering framework that can be used to
analyze, disassemble, and debug your ARM64 assembly binaries. This guide covers
the basics of using r2 to understand your compiled code.

## Opening a Binary

### Basic Analysis

Open your binary with automatic analysis:

```bash
r2 -A build/drift
```

The `-A` flag performs automatic analysis, identifying functions, strings, and
code structures.

### Non-Interactive Mode

To quickly view disassembly without entering interactive mode:

```bash
r2 -A build/drift -c "pdf @entry0"
```

This opens the binary, analyzes it, prints the disassembly of `entry0`, and
exits.

## Finding Your Code

### Listing Functions

Once inside r2, list all functions:

```r2
afl
```

This shows all functions, including `entry0` (which is r2's name for your
`_start` function).

### Seeking to a Function

Navigate to a specific function:

```r2
# Seek to entry0 (your _start function)
s entry0

# Or seek to any function by name
s <function_name>
```

After seeking, your prompt changes to show the current address:

```
[0xaaaab0410244]>
```

## Viewing Assembly Code

### Print Disassembly Function

After seeking to a function, print its disassembly:

```r2
pdf
```

This prints the disassembly of the current function with:

- Memory addresses
- Hexadecimal opcodes
- ARM64 assembly instructions
- Comments showing section information

### Print Disassembly at Address

View disassembly at a specific address:

```r2
# Print disassembly of entry0 without seeking
pdf @entry0

# Print N instructions from current position
pd 20

# Print disassembly at a specific address
pd 10 @0xaaaab0410244
```

## Understanding the Output

### Mapping r2 Output to Your Source

When r2 disassembles your code, you'll see differences from your source:

**Your Source:**

```asm
mov x0, #STDOUT_FILENO
adr x1, msg
mov x2, #msg_len
mov x8, #64
svc #0
```

**r2 Disassembly:**

```
movz x0, 0x1
adr x1, loc.msg
movz x2, 0x1b
movz x8, 0x40
svc 0
```

**Key Differences:**

1. **`mov` → `movz`**: Your `mov` pseudo-instruction becomes `movz` (move with
   zero) for immediate values. This is normal and correct.

2. **Constants Resolved**: All constants are shown as their actual values:
   - `STDOUT_FILENO` (1) → `0x1`
   - `msg_len` (27) → `0x1b` (hex for 27)
   - `64` (write syscall) → `0x40`
   - `93` (exit syscall) → `0x5d`

3. **Label Names**: r2 may rename labels (e.g., `msg` → `loc.msg`), but they
   refer to the same memory location.

### Reading the Disassembly Format

Each line in `pdf` output shows:

```
<address>  <hex_opcode>  <instruction>  ; [comments]
```

Example:

```
0xaaaab0410244  200080d2  movz x0, 0x1    ; [06] -r-x section size 32 named .text
```

- `0xaaaab0410244`: Memory address of the instruction
- `200080d2`: Hexadecimal representation of the instruction
- `movz x0, 0x1`: Human-readable ARM64 assembly
- `; [06] -r-x section...`: Metadata about the section

## Viewing Data Sections

### Listing Strings

View all strings in your binary:

```r2
iz
```

This shows:

- String labels (like `msg:`)
- The actual string content
- Memory addresses
- String lengths

Example output:

```
0xaaaab0410264  str.Hello_from_Drift_on_ARM64_n:  "Hello from Drift on ARM64!\n"  ; len=27
```

### Viewing Sections

List all sections in the binary:

```r2
iS
```

This shows:

- Section names (`.text`, `.rodata`, etc.)
- Section addresses
- Section sizes
- Section permissions (read, write, execute)

### Viewing Specific Data

```r2
# View data at a specific address
px @msg          # Print hex dump at msg
ps @msg          # Print string at msg
pf @msg          # Print formatted data at msg
```

## Cross-References

### Finding References

See where a function or symbol is referenced:

```r2
# Show where entry0 is referenced
axt @entry0

# Show where msg is referenced
axt @msg

# Show what entry0 references
axf @entry0
```

This helps understand how your code connects to data and other functions.

## Visual Mode

Enter interactive visual mode:

```r2
V
```

In visual mode:

- **`p`**: Cycle through views (hex, disassembly, graph, etc.)
- **`j`/`k`**: Move up/down
- **`h`/`l`**: Move left/right
- **`?`**: Show help
- **`q`**: Exit visual mode (press multiple times to exit r2)

Visual mode provides a more interactive way to explore your binary.

## Common Workflow

### Complete Analysis Session

```r2
# 1. Open and analyze
r2 -A build/drift

# 2. List functions
afl

# 3. Seek to entry point
s entry0

# 4. View disassembly
pdf

# 5. View strings
iz

# 6. Check cross-references
axt @entry0

# 7. Enter visual mode for exploration
V
```

### Quick One-Liner

```bash
r2 -A build/drift -c "pdf @entry0; iz"
```

This prints both the function disassembly and all strings.

## Useful Commands Reference

### Navigation

- `s <address>`: Seek to address
- `s+`: Seek forward
- `s-`: Seek backward
- `s entry0`: Seek to function

### Disassembly

- `pdf`: Print disassembly function (current)
- `pdf @<name>`: Print disassembly of named function
- `pd N`: Print N instructions
- `pd N @<addr>`: Print N instructions at address

### Information

- `afl`: List all functions
- `iz`: List strings
- `iS`: List sections
- `is`: List symbols
- `ii`: List imports
- `il`: List libraries

### Analysis

- `aa`: Analyze all (auto-analysis)
- `axt @<name>`: Show references to symbol
- `axf @<name>`: Show what symbol references

### Memory/Data

- `px @<addr>`: Print hex dump
- `ps @<addr>`: Print string
- `pf @<addr>`: Print formatted data

### Visual

- `V`: Enter visual mode
- `VV`: Enter graph view
- `V!`: Enter visual panels mode

### Exiting

- `q`: Quit (may need to press multiple times)

## Tips for Understanding Your Code

1. **Start with `afl`**: Always list functions first to see what r2 found.

2. **Use `pdf @entry0`**: This is your `_start` function - start here.

3. **Check `iz`**: See your strings to understand data references.

4. **Follow `adr` instructions**: When you see `adr x1, loc.msg`, use `iz` to
   find where `msg` actually is.

5. **Compare addresses**: The addresses in disassembly match addresses shown in
   `iz` and `iS` output.

6. **Use visual mode**: Press `V` and cycle through views with `p` to see
   different representations of your code.

## Example: Mapping Your Source to r2 Output

**Your Source (`src/hello.s`):**

```asm
_start:
    mov x0, #STDOUT_FILENO    # Load stdout file descriptor
    adr x1, msg                # Load address of message
    mov x2, #msg_len           # Load message length
    mov x8, #64                # Load write syscall number
    svc #0                     # Make system call
```

**r2 Disassembly:**

```
0xaaaab0410244  200080d2  movz x0, 0x1      ; x0 = 1 (STDOUT_FILENO)
0xaaaab0410248  e1000010  adr x1, loc.msg   ; x1 = address of msg string
0xaaaab041024c  620380d2  movz x2, 0x1b     ; x2 = 27 (msg_len)
0xaaaab0410250  080880d2  movz x8, 0x40     ; x8 = 64 (write syscall)
0xaaaab0410254  010000d4  svc 0             ; Make system call
```

**Correspondence:**

- Line 1: `mov x0, #STDOUT_FILENO` → `movz x0, 0x1` (constant resolved to 1)
- Line 2: `adr x1, msg` → `adr x1, loc.msg` (label renamed, same address)
- Line 3: `mov x2, #msg_len` → `movz x2, 0x1b` (calculated length = 27 bytes)
- Line 4: `mov x8, #64` → `movz x8, 0x40` (64 in hex = 0x40)
- Line 5: `svc #0` → `svc 0` (same instruction)

The code is correct - r2 is showing the final compiled instructions with all
constants and addresses resolved.

## Debugging with r2

While r2 can be used for debugging, for ARM64 assembly development, `lldb` is
typically more suitable (see `debugging.md`). However, r2 can be useful for:

- Quick disassembly checks
- Understanding binary structure
- Analyzing how your code compiled
- Exploring data sections

For interactive debugging with breakpoints and step-through execution, use
`lldb` or the `just debug` command.
