# References

## ARM64 Linux Syscall Table

**URL:** https://syscalls.mebeim.net/?table=arm64/64/aarch64/latest

A comprehensive reference for ARM64 Linux system calls. This table shows:

- **Syscall numbers** - The numeric ID used in the `x8` register when making
  syscalls
- **Function signatures** - C-style function declarations showing parameters and
  return types
- **Register mapping** - How C function arguments map to ARM64 registers
  (`x0`-`x5`)
- **Kernel versions** - Which syscalls are available in different kernel
  versions

### Usage in Assembly

When making a syscall in ARM64 assembly:

1. Load arguments into `x0` through `x5` (in order)
2. Load the syscall number into `x8`
3. Execute `svc #0` to invoke the syscall
4. Read the return value from `x0`

### Common Syscalls

- **64** - `write(int fd, const void *buf, size_t count)` - Write to a file
  descriptor
- **93** - `exit(int status)` - Terminate the calling process
- **63** - `read(int fd, void *buf, size_t count)` - Read from a file descriptor
- **56** - `open(const char *pathname, int flags, ...)` - Open a file
- **57** - `close(int fd)` - Close a file descriptor

This reference is essential when writing ARM64 assembly code that needs to
interact with the Linux kernel.
