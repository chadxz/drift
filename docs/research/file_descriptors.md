# File Descriptors

## Standard File Descriptors

In Unix-like systems (including Linux), every process has three standard file
descriptors automatically opened:

- **0** - `stdin` (standard input) - Used for reading input data
- **1** - `stdout` (standard output) - Used for writing normal output
- **2** - `stderr` (standard error) - Used for writing error messages

These file descriptors are reserved by the operating system and are available to
every process by default. They're essential for I/O operations and are commonly
used in shell redirection and piping.

## Usage in System Calls

When making system calls like `write()` or `read()`, the first argument is the
file descriptor number:

```c
ssize_t write(int fd, const void *buf, size_t count);
ssize_t read(int fd, void *buf, size_t count);
```

For example:

- `write(1, "Hello\n", 6)` writes to stdout
- `write(2, "Error\n", 6)` writes to stderr
- `read(0, buffer, size)` reads from stdin

## Assigning File Descriptors to Constants in Assembly

In our ARM64 assembly code, we use the `.equ` directive (GAS/AT&T syntax) to
assign file descriptor numbers to symbolic constants. This makes the code more
readable and maintainable.

### Example from `src/hello.s`

```assembly
.equ STDOUT_FILENO, 1
```

This creates a symbolic constant `STDOUT_FILENO` that equals `1`. When we need
to write to stdout, we can use:

```assembly
mov x0, #STDOUT_FILENO  # Load stdout file descriptor (1) into x0
```

### Benefits of Using Constants

1. **Readability** - `STDOUT_FILENO` is more meaningful than the magic number
   `1`
2. **Maintainability** - If we need to change the value, we only update it in
   one place
3. **Self-documentation** - The constant name explains what the value represents
4. **Consistency** - Matches common C conventions (e.g., `<unistd.h>` defines
   `STDOUT_FILENO`)

### Recommended Constants

For consistency with POSIX standards and C conventions, we should define:

```assembly
.equ STDIN_FILENO,  0
.equ STDOUT_FILENO, 1
.equ STDERR_FILENO, 2
```

These constants can then be used throughout the assembly code when making
syscalls that require file descriptors.
