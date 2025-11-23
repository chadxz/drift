# Program Termination

## What Happens Without Explicit Exit

If you don't explicitly call the `exit()` syscall in your assembly program, the
CPU will continue executing instructions sequentially after your code ends. This
leads to **undefined behavior** and typically results in a **segmentation fault
(SIGSEGV)**.

### Why It Crashes

1. **Execution continues past your code** - The CPU doesn't know your program is
   "done". It will keep fetching and executing instructions from memory.

2. **Invalid memory access** - After your code section ends, the CPU will try to
   execute whatever bytes happen to be in memory:
   - Uninitialized memory (often zeros or random data)
   - Data sections (not executable code)
   - Memory that isn't mapped/accessible
   - Padding bytes or other non-instruction data

3. **Segmentation fault** - When the CPU tries to:
   - Execute invalid instruction encodings
   - Access memory that isn't executable
   - Access unmapped memory regions

   The kernel will send a `SIGSEGV` signal to your process, terminating it with
   an error.

### Example Behavior

If you remove the `exit()` syscall from `src/hello.s`:

```assembly
_start:
    # write(STDOUT_FILENO, msg, len)
    mov x0, #STDOUT_FILENO
    adr x1, msg
    sub x2, x1, x1
    add x2, x2, #(msg_end - msg)
    mov x8, #64
    svc #0
    
    # Missing exit() - program will crash!
```

Running this would produce output like:

```
Hello from Drift on ARM64!
Segmentation fault (core dumped)
```

### Exit Syscall Details

The `exit()` syscall (number 93 on ARM64 Linux) is the proper way to terminate
your program:

```assembly
# exit(0)
mov x0, #0      # Exit status code (0 = success)
mov x8, #93     # Syscall number for exit
svc #0          # Invoke syscall
```

**Exit status codes:**

- `0` - Success (conventional)
- Non-zero - Error/failure (conventional, specific meaning is
  application-defined)

### Why C Programs Don't Need This

In C programs, you typically don't write `exit()` explicitly because:

1. **C Runtime (CRT)** - C programs link against the C runtime library, which
   provides a `_start` function that:
   - Sets up the environment
   - Calls `main()`
   - Calls `exit()` when `main()` returns

2. **Return from main** - When `main()` returns, the CRT calls `exit()` with the
   return value

In pure assembly (no CRT/libc), you must explicitly call `exit()` because
there's no runtime to do it for you.

### Best Practice

**Always explicitly call `exit()`** at the end of your `_start` function in
assembly programs. This ensures:

- Clean program termination
- Proper exit status reporting
- No undefined behavior
- Predictable program behavior
