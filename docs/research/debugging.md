# Debugging ARM64 Assembly

## Building with Debug Symbols

To debug your assembly code, you need to build with debug symbols using the `-g`
flag:

```bash
just build-debug
```

Or manually:

```bash
clang --target=aarch64-linux-gnu \
    -nostdlib \
    -g \
    -Wl,--gc-sections \
    -o build/drift \
    src/hello.s
```

The `-g` flag tells the compiler to include debug information in the binary,
which allows the debugger to map machine code back to your source code.

## Starting the Debugger

Use the `debug` target to build with debug symbols and start `lldb`:

```bash
just debug
```

Or start `lldb` manually:

```bash
lldb build/drift
```

## Basic LLDB Commands

### Running the Program

```lldb
(lldb) run
# or
(lldb) r
```

This starts execution of your program.

### Setting Breakpoints

Set breakpoints at specific locations:

```lldb
# Break at the entry point
(lldb) breakpoint set --name _start
# or
(lldb) b _start

# Break at a specific line (if you have line number info)
(lldb) breakpoint set --file src/hello.s --line 12

# Break at a label
(lldb) b msg
```

### Stepping Through Code

```lldb
# Step into (execute one instruction, enter functions)
(lldb) step
# or
(lldb) s

# Step over (execute one instruction, don't enter functions)
(lldb) next
# or
(lldb) n

# Continue execution until next breakpoint
(lldb) continue
# or
(lldb) c

# Finish current function
(lldb) finish
```

### Inspecting Registers

ARM64 has 31 general-purpose registers (`x0`-`x30`) plus special registers:

```lldb
# View all registers
(lldb) register read

# View specific register
(lldb) register read x0
(lldb) register read x1
(lldb) register read x8    # Syscall number
(lldb) register read pc     # Program counter

# View registers in different formats
(lldb) register read x0 --format hex
(lldb) register read x0 --format decimal
```

### Inspecting Memory

```lldb
# Print memory at an address
(lldb) memory read 0x1000

# Print memory as string
(lldb) memory read --format c --count 32 <address>

# Print memory as assembly
(lldb) memory read --format instruction <address>

# Print value at a label
(lldb) print (char*)msg
```

### Disassembling Code

```lldb
# Disassemble current function
(lldb) disassemble
# or
(lldb) dis

# Disassemble specific function
(lldb) disassemble --name _start

# Disassemble around current PC
(lldb) disassemble --start-address $pc-20 --count 10
```

### Viewing Source Code

```lldb
# List current source location
(lldb) list
# or
(lldb) l

# List specific function
(lldb) list _start

# Show current location
(lldb) frame info
```

### Inspecting Variables and Symbols

```lldb
# Print value of a symbol
(lldb) print msg
(lldb) print msg_len

# Print address of a symbol
(lldb) print &msg

# Print string at address
(lldb) print (char*)msg
```

## Common Debugging Workflows

### 1. Debug from Entry Point

```lldb
(lldb) b _start
(lldb) run
(lldb) step    # Step through each instruction
```

### 2. Inspect Before Syscall

```lldb
(lldb) b _start
(lldb) run
(lldb) step    # Step until you reach the syscall
(lldb) register read x0 x1 x2 x8  # Check syscall arguments
(lldb) step    # Execute syscall
```

### 3. Inspect String Data

```lldb
(lldb) b _start
(lldb) run
(lldb) print &msg              # Get address of msg
(lldb) memory read --format c --count 32 <address>  # Print string
```

### 4. Debug Syscall Issues

```lldb
(lldb) b _start
(lldb) run
# Step to syscall instruction (svc #0)
(lldb) register read x0 x1 x2 x8  # Verify arguments
(lldb) step                       # Execute syscall
(lldb) register read x0           # Check return value
```

## ARM64 Register Conventions

Understanding ARM64 register usage helps with debugging:

- **x0-x7**: Arguments to functions/syscalls, return values
- **x8**: Syscall number (when making syscalls)
- **x9-x15**: Temporary registers (caller-saved)
- **x16-x17**: IP0/IP1 (intra-procedure call registers)
- **x19-x28**: Callee-saved registers
- **x29**: Frame pointer (FP)
- **x30**: Link register (LR) - return address
- **sp**: Stack pointer
- **pc**: Program counter

### Syscall Register Mapping

When making syscalls:

- **x0**: First argument (fd for write/read)
- **x1**: Second argument (buffer pointer)
- **x2**: Third argument (count/size)
- **x8**: Syscall number (64 for write, 93 for exit)
- **x0**: Return value after syscall

## Debugging Tips

1. **Always build with `-g`** - Without debug symbols, you'll only see raw
   addresses and disassembly

2. **Use breakpoints strategically** - Set breakpoints before syscalls to
   inspect arguments

3. **Check return values** - After syscalls, check `x0` for return values
   (negative = error)

4. **Inspect memory carefully** - Use `memory read` with appropriate formats to
   see what's actually in memory

5. **Watch the program counter** - `register read pc` shows where you are in
   execution

6. **Use `frame info`** - Shows current execution context

## Example Debug Session

```lldb
$ lldb build/drift
(lldb) target create "build/drift"
Current executable set to 'build/drift' (aarch64).
(lldb) breakpoint set --name _start
Breakpoint 1: where = drift`_start + 4, address = 0x0000000000401000
(lldb) run
Process 12345 launched: 'build/drift' (aarch64)
Process 12345 stopped
* thread #1, stop reason = breakpoint 1.1
    frame #0: 0x0000000000401000 drift`_start
drift`_start:
->  0x401000 <+4>:  mov    x0, #0x1
    0x401004 <+8>:  adr    x1, #0x8
    0x401008 <+12>: mov    x2, #0x1c
    0x40100c <+16>: mov    x8, #0x40
(lldb) register read
General Purpose Registers:
        x0 = 0x0000000000000000
        x1 = 0x0000000000000000
        x2 = 0x0000000000000000
        x8 = 0x0000000000000000
       ...
(lldb) step
Process 12345 stopped
* thread #1, stop reason = step in
    frame #0: 0x0000000000401004 drift`_start + 8
    frame #1: 0x0000000000401004 drift`_start + 8
drift`_start:
->  0x401004 <+8>:  adr    x1, #0x8
    0x401008 <+12>: mov    x2, #0x1c
    0x40100c <+16>: mov    x8, #0x40
    0x401010 <+20>: svc    #0x0
(lldb) register read x0
      x0 = 0x0000000000000001
(lldb) continue
Process 12345 exited with status = 0
```

## Alternative: Using GDB

If you prefer GDB over LLDB:

```bash
gdb build/drift
```

GDB commands are similar but slightly different syntax:

- `break _start` instead of `breakpoint set --name _start`
- `info registers` instead of `register read`
- `x/32c <address>` instead of `memory read --format c`

## Using radare2 (r2) for Debugging

radare2 is a powerful reverse engineering framework that can also debug
binaries. It provides a different interface with visual modes and extensive
analysis capabilities.

### Starting radare2 in Debug Mode

```bash
r2 -d build/drift
```

The `-d` flag starts radare2 in debug mode, attaching to the binary.

### Basic radare2 Debugging Commands

```r2
# Analyze the binary
[0x00000000]> aa

# Set breakpoint at _start
[0x00000000]> db _start

# Start execution
[0x00000000]> dc

# Continue execution
[0x00000000]> dc

# Step one instruction
[0x00000000]> ds

# Step over (next instruction)
[0x00000000]> dso

# View registers
[0x00000000]> dr

# View specific register
[0x00000000]> dr x0
[0x00000000]> dr x1
[0x00000000]> dr x8

# View all registers in detail
[0x00000000]> drr

# Disassemble current location
[0x00000000]> pd

# Disassemble _start function
[0x00000000]> pdf @_start

# View memory
[0x00000000]> px 32 @msg          # Hex dump at msg
[0x00000000]> ps @msg             # String at msg

# Visual graph mode (very useful!)
[0x00000000]> VV

# Visual mode (split view)
[0x00000000]> V

# Exit visual mode: press 'q'
```

### radare2 Visual Modes

radare2 has powerful visual interfaces:

1. **Visual Mode** (`V`) - Split screen with disassembly, registers, and
   commands
2. **Visual Graph Mode** (`VV`) - Graph view showing control flow
3. **Visual Panels** (`V!`) - Multiple panels showing different views

### Example radare2 Debug Session

```r2
$ r2 -d build/drift
[0x00000000]> aa                    # Analyze all
[0x00000000]> db _start             # Set breakpoint
[0x00000000]> dc                    # Continue to breakpoint
hit breakpoint at: 0x401000
[0x00401000]> pd                    # Print disassembly
[0x00401000]> dr                    # Show registers
[0x00401000]> ds                    # Step one instruction
[0x00401004]> dr x0                 # Check x0 register
[0x00401004]> px 32 @msg            # View string at msg
[0x00401004]> VV                    # Enter visual graph mode
```

### radare2 Advantages

- **Visual graph mode** - See control flow visually
- **Multiple views** - Disassembly, registers, memory, stack simultaneously
- **Powerful analysis** - Automatic analysis, cross-references
- **Scripting** - Can be scripted with r2pipe
- **Cross-platform** - Works on many platforms

### radare2 vs LLDB

**radare2:**

- Better for reverse engineering and analysis
- Visual graph mode for control flow
- More complex but more powerful
- Good for understanding binary structure

**LLDB:**

- More traditional debugger interface
- Better integration with development tools
- Simpler for basic debugging
- Standard for development workflows

Both are useful - use radare2 when you want visual analysis and reverse
engineering features, use LLDB for standard debugging workflows.

## Debugging in Docker Container

To debug inside the development container:

```bash
# With LLDB
just dev-run "lldb build/drift"

# With radare2 (if installed)
just dev-run "r2 -d build/drift"
```

Or start an interactive session:

```bash
just dev
# Inside container:
lldb build/drift
# or
r2 -d build/drift
```

**Note:** radare2 may need to be installed in your Docker container. Add it to
`Dockerfile.dev` if you want to use it:

```dockerfile
RUN apt-get install -y radare2
```
