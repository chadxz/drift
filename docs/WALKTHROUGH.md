# Drift: End-to-End Walkthrough

> From first `hello world` in ARM64 assembly to a working HTTP server, then
> deployment on OCI using Docker, GHCR, Packer, and Terraform.

This walkthrough takes you **from zero to a deployed Drift web server**:

**Part A: Building the Web Server (Assembly)**

1. Minimal hello world (stdout)
2. Create a TCP socket (IPv6 dual-stack)
3. Bind to a port
4. Listen for connections
5. Accept a connection
6. Read the HTTP request
7. Send an HTTP response
8. Handle multiple connections (loop) + socket options

**Part B: Packaging & Deployment**

9. Docker image for ARM64
10. GitHub Container Registry (GHCR)
11. OCI infrastructure with Packer + Terraform
12. Deploy and go live

Assumptions:

- Host: macOS on Apple Silicon
- You're comfortable with: shell, Git/GitHub, Docker, jj, Helix
- You have or will create: GitHub account, OCI Free Tier account

### Who this walkthrough is for

- **Audience**: curious systems/programming folks who are comfortable in the
  shell and want to see an end-to-end path from ARM64 assembly to a live HTTP
  endpoint.
- **Time commitment**:
  - **Part A (web server in assembly)**: roughly 1–3 focused hours, depending on
    your assembly and networking background.
  - **Part B (packaging + OCI infra)**: another ~1–3 hours the first time you
    wire up Packer/Terraform/OCI.

You can safely stop after **Part A** if you only care about the
assembly/web-server side; come back to **Part B** whenever you want to deploy
it.

### 🛠️ Pre-flight Check

Ensure you have the necessary tools installed:

```bash
just --version
docker --version
packer --version
terraform --version
```

**Platform notes (Apple Silicon focus):**

- **macOS on Apple Silicon**: all Docker commands here assume you are running on
  an ARM64 host (Docker Desktop or colima) and explicitly use
  `--platform=linux/arm64` so containers match the target environment.
- **Other platforms**: if you're on x86_64 Linux or macOS, you'll need either an
  ARM64 machine/VM or an emulator (such as QEMU) and may need to adjust the
  `--platform` flags and OCI image shape.
- **Docker Buildx**: modern Docker Desktop includes Buildx; if `docker buildx`
  is missing, install/update Docker before attempting the `build-image` step in
  Part B.

---

## 0. High-Level Architecture

1. **Code**: Drift is an ARM64 Linux ELF binary, written in **AArch64 (ARM64)
   GAS/Clang-style assembly**.
2. **Local dev**:
   - Build using `clang --target=aarch64-linux-gnu`
   - Wrap commands with `just`
   - Run/test in a local ARM64 Linux Docker container
3. **Packaging**:
   - Build an ARM64 Docker image for Drift
   - Push to GitHub Container Registry (GHCR)
4. **Infra**:
   - Use **Packer** to create an ARM64 OCI base image (Ubuntu + Docker)
   - Use **Terraform** to provision VCN, subnet, and VM instance
5. **Deployment**:
   - Build + push Docker image to GHCR
   - SSH into VM, pull image, restart container on port 80

---

# Part A: Building the Web Server

---

## 1. Bootstrap the Project

### 1.1 Create the repo

```bash
mkdir drift
cd drift
jj init .
git init
```

(Optional: connect GitHub remote later.)

Add a basic `.gitignore`:

```gitignore
/build
/.jj
.DS_Store
.idea
.vscode
```

### 1.2 Directory structure

```bash
mkdir -p src docs/research
```

Commit:

```bash
jj commit -m "Bootstrap Drift repo"
```

If you're new to some of the tools used here, these are good starting points:

- **`just`**: [Just command runner](https://github.com/casey/just) — simple,
  reproducible command recipes.
- **`jj`**: [Jujutsu (jj) VCS](https://github.com/martinvonz/jj) — a modern
  version-control system that can interoperate with Git.
- **Helix**: [Helix editor](https://helix-editor.com/) — modal text editor with
  good language support.
- **Docker**:
  [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)
  or [colima](https://github.com/abiosoft/colima) — container runtime for
  running the ARM64 dev environment.

---

## 2. Minimal ARM64 Assembly Hello World

Our first goal: prove we can build and run ARM64 assembly.

### 📚 Concepts to understand

Before writing code, review these concepts:

| Concept                   | Resource                                                                                                                       | What you'll learn                                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------- |
| ARM64 registers           | [ARM Registers Overview](https://developer.arm.com/documentation/102374/0101/Registers-in-AArch64---general-purpose-registers) | x0-x30 general purpose registers, their roles         |
| Syscall convention        | [docs/research/syscalls.md](research/syscalls.md)                                                                              | How to invoke Linux kernel functions                  |
| Entry point               | [docs/research/entry_point.md](research/entry_point.md)                                                                        | Why `_start` is the entry point, not `main`           |
| Sections & constants      | [docs/research/constants_and_sections.md](research/constants_and_sections.md)                                                  | `.text`, `.rodata`, `.data`, `.bss` sections          |
| Program termination       | [docs/research/program_termination.md](research/program_termination.md)                                                        | Why you must call `exit()` explicitly                 |
| ARM64 assembly tutorial   | [docs/research/azeria_labs_arm_assembly.md](research/azeria_labs_arm_assembly.md)                                              | Step-by-step ARM64 assembly intro and exercises       |
| Books & longer references | [docs/research/books.md](research/books.md)                                                                                    | Deeper systems, assembly, networking, and infra texts |

**Key ARM64 syscall registers:**

```
x0-x5  → syscall arguments (in order)
x8     → syscall number
svc #0 → trigger syscall
x0     → return value (after syscall)
```

**Syscalls we'll use:**

| Syscall | Number | Signature               |
| ------- | ------ | ----------------------- |
| `write` | 64     | `write(fd, buf, count)` |
| `exit`  | 93     | `exit(status)`          |

### 2.1 Write `src/hello.s`

This uses Linux ARM64 syscalls: `write` (64) and `exit` (93).

```asm
// src/hello.s — Minimal hello world

.equ STDOUT_FILENO, 1
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93

.section .rodata
msg:
    .ascii "Hello from Drift on ARM64!\n"
msg_len = . - msg

.section .text
.global _start

_start:
    // write(STDOUT_FILENO, msg, msg_len)
    mov     x0, #STDOUT_FILENO
    adr     x1, msg
    mov     x2, #msg_len
    mov     x8, #SYS_WRITE
    svc     #0

    // exit(0)
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0
```

**Line-by-line breakdown:**

- `.equ` — defines compile-time constants (no memory allocated)
- `.section .rodata` — read-only data section for our string
- `.ascii` — raw string bytes (no null terminator)
- `msg_len = . - msg` — calculates length using current position (`.`) minus
  `msg`
- `.global _start` — exports symbol so linker can find entry point
- `mov x0, #STDOUT_FILENO` — load immediate value into register
- `adr x1, msg` — load address of `msg` into x1 (PC-relative addressing)
- `svc #0` — supervisor call (syscall trap)

### 2.2 Create a dev container for building/testing

Create `Dockerfile.dev` for a repeatable ARM64 Linux build environment:

```dockerfile
# Dockerfile.dev — ARM64 Linux dev environment
FROM --platform=linux/arm64 ubuntu:24.04

RUN apt-get update && \
    apt-get install -y clang lld make strace binutils file && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
```

### 2.3 Add initial justfile

Create `justfile` in project root:

```just
# justfile — Drift build recipes

default: help

help:
    @echo "Drift — ARM64 Assembly Web Server"
    @echo ""
    @echo "Development:"
    @echo "  just build          - Build the binary"
    @echo "  just run            - Build and run in container"
    @echo "  just strace         - Run with strace to see syscalls"
    @echo "  just inspect        - Inspect the binary (size, sections, symbols)"
    @echo "  just shell          - Open shell in dev container"
    @echo ""

# Build dev container
build-dev:
    docker build --platform linux/arm64 -f Dockerfile.dev -t drift-dev .

# Build the Drift binary inside dev container
build: build-dev
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        sh -c 'mkdir -p build && clang --target=aarch64-linux-gnu -nostdlib \
            -Wl,-e,_start -Wl,--gc-sections \
            -o build/drift src/hello.s'

# Run the binary in dev container
run: build
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        ./build/drift

# Run with strace to see syscalls
strace: build
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        strace -f ./build/drift

# Inspect binary: size, sections, symbols, disassembly
inspect: build
    @echo "=== File type and size ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        sh -c 'file build/drift && ls -lh build/drift'
    @echo ""
    @echo "=== Section headers ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        readelf -S build/drift
    @echo ""
    @echo "=== Symbol table ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        nm build/drift
    @echo ""
    @echo "=== Disassembly ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        objdump -d build/drift

# Open an interactive shell in dev container
shell: build-dev
    docker run -it --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        /bin/bash
```

### 2.4 Test it

```bash
just run
```

You should see:

```text
Hello from Drift on ARM64!
```

🎉 Congratulations! You've built and run your first ARM64 assembly program.

### 🔬 Inspect your binary

Let's see what we actually built:

```bash
just inspect
```

**Example output:**

```text
=== File type and size ===
build/drift: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), 
             statically linked, not stripped
-rwxr-xr-x 1 root root 1.4K Nov 26 12:00 build/drift

=== Section headers ===
There are 7 section headers, starting at offset 0x1d0:

Section Headers:
  [Nr] Name              Type             Address           Offset    Size
  [ 1] .text             PROGBITS         00000000004000b0  000000b0  0000002c
  [ 2] .rodata           PROGBITS         00000000004000dc  000000dc  0000001b
  ...

=== Symbol table ===
00000000004000dc r msg
00000000004000f7 r msg_len
00000000004000b0 T _start

=== Disassembly ===
build/drift:     file format elf64-littleaarch64

Disassembly of section .text:

00000000004000b0 <_start>:
  4000b0:       d2800020        mov     x0, #0x1      // fd = 1 (stdout)
  4000b4:       10000141        adr     x1, 4000dc    // buf = &msg
  4000b8:       d2800362        mov     x2, #0x1b     // count = 27
  4000bc:       d2800808        mov     x8, #0x40     // syscall 64 (write)
  4000c0:       d4000001        svc     #0x0
  4000c4:       d2800000        mov     x0, #0x0      // status = 0
  4000c8:       d2800ba8        mov     x8, #0x5d     // syscall 93 (exit)
  4000cc:       d4000001        svc     #0x0
```

**What you learned:**

- Your binary is only **~1.4KB** — no libc, no bloat!
- The disassembly shows exactly what your assembly became
- `0x40` = 64 (write), `0x5d` = 93 (exit), `0x1b` = 27 (msg length)
- Symbols like `_start` and `msg` are visible in the binary

For more on ELF layout and binary structure, see
[`docs/research/elf_format.md`](research/elf_format.md). For an additional
disassembler/debugger workflow, see
[`docs/research/radare2.md`](research/radare2.md).

### 🔍 Watch syscalls with strace

See your program talk to the kernel in real-time:

```bash
just strace
```

**Example output:**

```text
execve("./build/drift", ["./build/drift"], 0xfffff...) = 0
write(1, "Hello from Drift on ARM64!\n", 27) = 27
exit(0)                                 = ?
+++ exited with 0 +++
```

**What you learned:**

- `write(1, "Hello from Drift...", 27)` — your syscall with exact arguments!
- `exit(0)` — clean termination
- This is exactly what your assembly code does, no magic

For a deeper dive into debugging techniques (including LLDB), see
[`docs/research/debugging.md`](research/debugging.md).

### 🏋️ Try it yourself

Before moving on, try these modifications to cement your understanding:

1. **Change the message** — Update the string to say something else. Does
   `msg_len` still work correctly?

2. **Exit with a different code** — Change `mov x0, #0` to `mov x0, #42` before
   exit. Run `just run && echo $?` to see the exit code.

3. **Write to stderr** — Change `STDOUT_FILENO` to `2` (stderr). The output
   should still appear but on a different stream.

4. **Remove the exit syscall** — Comment out the exit code and run. What
   happens? (Hint: check
   [docs/research/program_termination.md](research/program_termination.md))

Commit:

```bash
jj commit -m "Add minimal ARM64 hello world assembly"
```

### 🔎 You are here

- **You built**: a minimal ARM64 Linux ELF that prints a message and exits
  cleanly.
- **You have**: a reproducible dev container plus `just` commands to build, run,
  `strace`, and inspect the binary.
- **Next**: turn this into a long-lived server by creating a TCP socket.

---

## 3. Create a TCP Socket (Dual-Stack IPv6)

Now we start building toward a web server. First step: create a socket.

We'll use **IPv6 with dual-stack** support, which means a single socket can
accept both IPv4 and IPv6 connections. This is the modern, recommended approach.

### 📚 Concepts to understand

| Concept               | Resource                                                                                | What you'll learn                        |
| --------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------- |
| Socket programming    | [Beej's Guide to Network Programming](https://beej.us/guide/bgnet/)                     | The classic guide to sockets             |
| `socket()` syscall    | [man 2 socket](https://man7.org/linux/man-pages/man2/socket.2.html)                     | Create an endpoint for communication     |
| Address families      | [man 7 address_families](https://man7.org/linux/man-pages/man7/address_families.7.html) | AF_INET, AF_INET6, AF_UNIX, etc.         |
| IPv6 dual-stack       | [man 7 ipv6](https://man7.org/linux/man-pages/man7/ipv6.7.html)                         | How IPv6 sockets can accept IPv4 clients |
| ARM64 syscall numbers | [syscalls.mebeim.net](https://syscalls.mebeim.net/?table=arm64/64/aarch64/latest)       | Complete ARM64 Linux syscall table       |

**Why IPv6 dual-stack?**

Instead of creating separate IPv4 and IPv6 sockets, we create one IPv6 socket
that accepts both:

- Native IPv6 connections (e.g., `[::1]:8080`)
- IPv4 connections mapped as IPv6 (e.g., `127.0.0.1` becomes `::ffff:127.0.0.1`)

This is controlled by the `IPV6_V6ONLY` socket option (we'll set it in a later
step).

**The socket syscall:**

```c
int socket(int domain, int type, int protocol);
// ARM64 syscall number: 198
```

**Arguments:**

| Register | Argument | Value             | Meaning                          |
| -------- | -------- | ----------------- | -------------------------------- |
| x0       | domain   | 10 (`AF_INET6`)   | IPv6 Internet protocols          |
| x1       | type     | 1 (`SOCK_STREAM`) | TCP (reliable, connection-based) |
| x2       | protocol | 0                 | Default protocol for type        |
| x8       | syscall# | 198               | `socket`                         |

**Return value (in x0):**

- Success: file descriptor (non-negative integer)
- Error: negative errno value

### 3.1 Update `src/hello.s` to create a socket

At a high level, here’s what changed compared to the hello world step:

```diff
// src/hello.s

-// src/hello.s — Minimal hello world
+// src/hello.s — Create a TCP socket (IPv6 dual-stack)

- .equ STDOUT_FILENO, 1
- .equ SYS_WRITE, 64
- .equ SYS_EXIT, 93
+ .equ STDOUT_FILENO, 1
+ .equ SYS_WRITE, 64
+ .equ SYS_EXIT, 93
+ .equ SYS_SOCKET, 198
+
+ .equ AF_INET6, 10
+ .equ SOCK_STREAM, 1
```

The full reference version at this step is:

```asm
// src/hello.s — Create a TCP socket (IPv6 dual-stack)

.equ STDOUT_FILENO, 1
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ SYS_SOCKET, 198

.equ AF_INET6, 10
.equ SOCK_STREAM, 1

.section .rodata
msg_socket_ok:
    .ascii "Socket created successfully!\n"
msg_socket_ok_len = . - msg_socket_ok

msg_socket_err:
    .ascii "Failed to create socket\n"
msg_socket_err_len = . - msg_socket_err

.section .text
.global _start

_start:
    // socket(AF_INET6, SOCK_STREAM, 0)
    mov     x0, #AF_INET6
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_SOCKET
    svc     #0

    // Check if socket creation succeeded (fd >= 0)
    cmp     x0, #0
    b.lt    socket_error

    // Save socket fd for later
    mov     x19, x0

    // Print success message
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_socket_ok
    mov     x2, #msg_socket_ok_len
    mov     x8, #SYS_WRITE
    svc     #0
    b       exit_ok

socket_error:
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_socket_err
    mov     x2, #msg_socket_err_len
    mov     x8, #SYS_WRITE
    svc     #0
    b       exit_err

exit_ok:
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0

exit_err:
    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0
```

**New concepts in this code:**

- `cmp x0, #0` — compare x0 with 0, sets condition flags
- `b.lt label` — branch if less than (signed comparison)
- `mov x19, x0` — save fd in x19 (callee-saved register, survives syscalls)
- `b label` — unconditional branch (like `goto`)

**Why x19?** Registers x19-x28 are "callee-saved" — they're preserved across
function calls and syscalls. x0-x18 can be clobbered.

### 3.2 Test it

```bash
just run
```

You should see:

```text
Socket created successfully!
```

### 🔍 Watch the socket syscall

```bash
just strace
```

```text
socket(AF_INET6, SOCK_STREAM, IPPROTO_IP) = 3
write(1, "Socket created successfully!\n", 29) = 29
exit(0)                                 = ?
```

The socket returned fd `3` (after stdin=0, stdout=1, stderr=2). Notice it shows
`AF_INET6` — this is our dual-stack socket.

### 🏋️ Try it yourself

1. **Try UDP instead of TCP** — Change `SOCK_STREAM` to `SOCK_DGRAM` (2). Does
   it still succeed?

2. **Try an invalid domain** — Change `AF_INET6` to `99`. What error message do
   you see? What does strace show for the return value?

3. **Try IPv4-only** — Change `AF_INET6` to `AF_INET` (2). It will work, but
   you'll lose IPv6 support. We'll stick with IPv6 dual-stack.

4. **Print the file descriptor** — This is harder! The fd is in x19. Can you
   print it? (Hint: you'd need to convert the integer to ASCII digits)

Commit:

```bash
jj commit -m "Add TCP socket creation (IPv6 dual-stack)"
```

### 🔎 You are here

- **You built**: an assembly program that creates an IPv6 TCP socket and reports
  success/failure.
- **You learned**: how to interpret syscall return values and store the socket
  fd for later use.
- **Next**: bind this socket to a specific port so clients can actually connect.

---

## 4. Bind to a Port

Now we bind our socket to an address and port.

### 📚 Concepts to understand

| Concept                 | Resource                                                                  | What you'll learn                |
| ----------------------- | ------------------------------------------------------------------------- | -------------------------------- |
| `bind()` syscall        | [man 2 bind](https://man7.org/linux/man-pages/man2/bind.2.html)           | Assign address to socket         |
| `sockaddr_in6` struct   | [man 7 ipv6](https://man7.org/linux/man-pages/man7/ipv6.7.html)           | IPv6 socket address structure    |
| Byte order (endianness) | [Beej's Guide - Byte Order](https://beej.us/guide/bgnet/html/#byte-order) | Network byte order is big-endian |
| `in6addr_any`           | [man 7 ipv6](https://man7.org/linux/man-pages/man7/ipv6.7.html)           | Bind to all interfaces (::)      |

**The bind syscall:**

```c
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
// ARM64 syscall number: 200
```

**The sockaddr_in6 structure (28 bytes):**

```c
struct sockaddr_in6 {
    uint16_t sin6_family;   // AF_INET6 (10)
    uint16_t sin6_port;     // Port in network byte order (big-endian!)
    uint32_t sin6_flowinfo; // Flow info (usually 0)
    uint8_t  sin6_addr[16]; // IPv6 address (in6addr_any = ::)
    uint32_t sin6_scope_id; // Scope ID (usually 0)
};
```

**Comparing IPv4 vs IPv6 address structures:**

| Field     | `sockaddr_in` (IPv4) | `sockaddr_in6` (IPv6) |
| --------- | -------------------- | --------------------- |
| Family    | `AF_INET` (2)        | `AF_INET6` (10)       |
| Port      | 2 bytes              | 2 bytes               |
| Flow info | —                    | 4 bytes               |
| Address   | 4 bytes              | 16 bytes              |
| Scope ID  | —                    | 4 bytes               |
| Padding   | 8 bytes              | —                     |
| **Total** | **16 bytes**         | **28 bytes**          |

**⚠️ Network byte order:** Port numbers must be in big-endian format. Port 8080
(0x1F90) becomes 0x901F when stored in memory on a little-endian system.

```
Port 8080 = 0x1F90
Big-endian (network order): 0x1F, 0x90
As 16-bit value on little-endian: 0x901F
```

**The IPv6 "any" address (`::`):** This is the IPv6 equivalent of `0.0.0.0`.
It's 16 bytes of zeros, meaning "bind to all interfaces."

### 4.1 Update `src/hello.s` to bind

Compared to the previous step, the key changes are:

```diff
// src/hello.s

 // Syscall numbers
 .equ SYS_SOCKET, 198
+.equ SYS_BIND, 200

 // Socket constants
 .equ AF_INET6, 10
 .equ SOCK_STREAM, 1
+
+// Port 8080 in big-endian: 0x1F90 → 0x901F
+.equ PORT_BE, 0x901F
```

The full reference version at this step is:

```asm
// src/hello.s — Create socket and bind to [::]:8080

.equ STDOUT_FILENO, 1
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200

.equ AF_INET6, 10
.equ SOCK_STREAM, 1

// Port 8080 in big-endian: 0x1F90 → 0x901F
.equ PORT_BE, 0x901F

.section .rodata
msg_socket_ok:
    .ascii "Socket created\n"
msg_socket_ok_len = . - msg_socket_ok

msg_bind_ok:
    .ascii "Bound to [::]:8080\n"
msg_bind_ok_len = . - msg_bind_ok

msg_error:
    .ascii "Error occurred\n"
msg_error_len = . - msg_error

.section .data
// sockaddr_in6 structure (28 bytes)
sockaddr:
    .hword AF_INET6         // sin6_family (2 bytes)
    .hword PORT_BE          // sin6_port (2 bytes, big-endian)
    .word  0                // sin6_flowinfo (4 bytes)
    .fill  16, 1, 0         // sin6_addr = :: (16 bytes of zeros)
    .word  0                // sin6_scope_id (4 bytes)
sockaddr_len = . - sockaddr

.section .text
.global _start

_start:
    // === Create socket ===
    mov     x0, #AF_INET6
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_SOCKET
    svc     #0
    cmp     x0, #0
    b.lt    error
    mov     x19, x0             // Save socket fd in x19

    // Print "Socket created"
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_socket_ok
    mov     x2, #msg_socket_ok_len
    mov     x8, #SYS_WRITE
    svc     #0

    // === Bind socket ===
    mov     x0, x19             // sockfd
    adr     x1, sockaddr        // addr
    mov     x2, #sockaddr_len   // addrlen (28 for IPv6)
    mov     x8, #SYS_BIND
    svc     #0
    cmp     x0, #0
    b.lt    error

    // Print "Bound to [::]:8080"
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_bind_ok
    mov     x2, #msg_bind_ok_len
    mov     x8, #SYS_WRITE
    svc     #0
    b       exit_ok

error:
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_error
    mov     x2, #msg_error_len
    mov     x8, #SYS_WRITE
    svc     #0
    b       exit_err

exit_ok:
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0

exit_err:
    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0
```

**New assembly directives:**

| Directive       | Size    | Purpose                        |
| --------------- | ------- | ------------------------------ |
| `.hword`        | 2 bytes | Half-word (16-bit value)       |
| `.word`         | 4 bytes | Word (32-bit value)            |
| `.fill N, S, V` | N×S     | Fill N items of S bytes with V |

### 4.2 Test it

```bash
just run
```

Expected output:

```text
Socket created
Bound to [::]:8080
```

### 🔍 Watch the bind syscall

```bash
just strace
```

```text
socket(AF_INET6, SOCK_STREAM, IPPROTO_IP) = 3
write(1, "Socket created\n", 15)        = 15
bind(3, {sa_family=AF_INET6, sin6_port=htons(8080), sin6_flowinfo=htonl(0), inet_pton(AF_INET6, "::", &sin6_addr), sin6_scope_id=0}, 28) = 0
write(1, "Bound to [::]:8080\n", 19)    = 19
exit(0)                                 = ?
```

Notice how strace decodes the sockaddr_in6 structure: it shows `AF_INET6`, the
port `htons(8080)`, and the address `::` (all zeros = bind to all interfaces).
The size is now 28 bytes instead of 16.

### 🏋️ Try it yourself

1. **Change the port to 3000** — Calculate the big-endian value for port 3000.
   (Hint: 3000 = 0x0BB8, so big-endian = 0xB80B)

2. **Bind to localhost only** — Change the 16 bytes of zeros to `::1`
   (loopback). The IPv6 loopback address is 15 bytes of 0x00 followed by 0x01.
   Verify with strace.

3. **Try binding twice** — Duplicate the bind syscall. What error do you get?
   What does strace show?

4. **Use a privileged port** — Try port 80 (0x5000 big-endian). What happens?
   (Hint: ports < 1024 require root)

Commit:

```bash
jj commit -m "Add socket bind to [::]:8080"
```

### 🔎 You are here

- **You built**: a socket server that successfully binds to `[::]:8080` (all
  interfaces, IPv4 and IPv6).
- **You learned**: how to lay out a `sockaddr_in6` struct in memory and handle
  byte order for ports.
- **Next**: mark the socket as a listening server with `listen()`.

---

## 5. Listen for Connections

### 📚 Concepts to understand

| Concept            | Resource                                                                                                          | What you'll learn                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| `listen()` syscall | [man 2 listen](https://man7.org/linux/man-pages/man2/listen.2.html)                                               | Mark socket as passive (server)     |
| TCP state machine  | [TCP States Diagram](https://users.cs.northwestern.edu/~aguMDT/cs340/project2/TCPIP_State_Transition_Diagram.pdf) | LISTEN, SYN_RCVD, ESTABLISHED, etc. |
| Backlog queue      | [man 2 listen - backlog](https://man7.org/linux/man-pages/man2/listen.2.html)                                     | Pending connection queue size       |

**The listen syscall:**

```c
int listen(int sockfd, int backlog);
// ARM64 syscall number: 201
```

**Arguments:**

| Register | Argument | Value         | Meaning                 |
| -------- | -------- | ------------- | ----------------------- |
| x0       | sockfd   | (from socket) | The server socket fd    |
| x1       | backlog  | 1-128         | Max pending connections |
| x8       | syscall# | 201           | `listen`                |

**What does backlog mean?** When clients connect faster than your server can
`accept()` them, they queue up. `backlog` limits this queue size. For a simple
server, 1-10 is fine. Production servers often use 128+.

### 5.1 Update `src/hello.s` to listen

This step mostly wires in one more syscall and a `print` helper:

```diff
// src/hello.s

 // Syscall numbers
 .equ SYS_SOCKET, 198
 .equ SYS_BIND, 200
+.equ SYS_LISTEN, 201

 // Server configuration
 .equ AF_INET6, 10
 .equ SOCK_STREAM, 1
 .equ PORT_BE, 0x901F
+.equ BACKLOG, 1
```

The full reference version at this step is:

```asm
// src/hello.s — Socket, bind, and listen (IPv6 dual-stack)

.equ STDOUT_FILENO, 1
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201

.equ AF_INET6, 10
.equ SOCK_STREAM, 1
.equ PORT_BE, 0x901F        // 8080 big-endian
.equ BACKLOG, 1

.section .rodata
msg_socket:
    .ascii "Socket created\n"
msg_socket_len = . - msg_socket

msg_bind:
    .ascii "Bound to [::]:8080\n"
msg_bind_len = . - msg_bind

msg_listen:
    .ascii "Listening for connections...\n"
msg_listen_len = . - msg_listen

msg_error:
    .ascii "Error occurred\n"
msg_error_len = . - msg_error

.section .data
// sockaddr_in6 structure (28 bytes)
sockaddr:
    .hword AF_INET6         // sin6_family (2 bytes)
    .hword PORT_BE          // sin6_port (2 bytes, big-endian)
    .word  0                // sin6_flowinfo (4 bytes)
    .fill  16, 1, 0         // sin6_addr = :: (16 bytes of zeros)
    .word  0                // sin6_scope_id (4 bytes)
sockaddr_len = . - sockaddr

.section .text
.global _start

_start:
    // === Create socket ===
    mov     x0, #AF_INET6
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_SOCKET
    svc     #0
    cmp     x0, #0
    b.lt    error
    mov     x19, x0

    adr     x1, msg_socket
    mov     x2, #msg_socket_len
    bl      print

    // === Bind ===
    mov     x0, x19
    adr     x1, sockaddr
    mov     x2, #sockaddr_len
    mov     x8, #SYS_BIND
    svc     #0
    cmp     x0, #0
    b.lt    error

    adr     x1, msg_bind
    mov     x2, #msg_bind_len
    bl      print

    // === Listen ===
    mov     x0, x19
    mov     x1, #BACKLOG
    mov     x8, #SYS_LISTEN
    svc     #0
    cmp     x0, #0
    b.lt    error

    adr     x1, msg_listen
    mov     x2, #msg_listen_len
    bl      print

    b       exit_ok

// Print helper: x1 = buffer, x2 = length
print:
    stp     x29, x30, [sp, #-16]!
    mov     x0, #STDOUT_FILENO
    mov     x8, #SYS_WRITE
    svc     #0
    ldp     x29, x30, [sp], #16
    ret

error:
    adr     x1, msg_error
    mov     x2, #msg_error_len
    bl      print
exit_err:
    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0

exit_ok:
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0
```

**New concepts: function calls and the stack**

| Instruction                 | Meaning                                                             |
| --------------------------- | ------------------------------------------------------------------- |
| `bl label`                  | Branch with link — jumps to label, saves return address in x30 (LR) |
| `ret`                       | Return — jumps to address in x30                                    |
| `stp x29, x30, [sp, #-16]!` | Store pair, pre-decrement SP (push to stack)                        |
| `ldp x29, x30, [sp], #16`   | Load pair, post-increment SP (pop from stack)                       |

**Why save x29/x30?** The `bl` instruction overwrites x30 with the return
address. If our `print` function calls a syscall (which it does), we need to
preserve x30 so we can return. x29 is the frame pointer, conventionally saved
together.

**Visualizing the stack:**

```text
Before call:           After stp (pre-decrement):
+------------+         +------------+
|            |         |            |
|            |         |     ...    |
|  Previous  |         +------------+ <- Old SP
|   Stack    |         |    x30     | (Return Address)
|            |         +------------+
|            |         |    x29     | (Frame Pointer)
+------------+ <- SP   +------------+ <- New SP
```

**📖 Further reading:**
[ARM64 Procedure Call Standard](https://developer.arm.com/documentation/102374/0101/Procedure-Call-Standard)

### 5.2 Test it

```bash
just run
```

Expected output:

```text
Socket created
Bound to [::]:8080
Listening for connections...
```

### 🔍 Watch the listen syscall

```bash
just strace
```

```text
socket(AF_INET6, SOCK_STREAM, IPPROTO_IP) = 3
write(1, "Socket created\n", 15)        = 15
bind(3, {sa_family=AF_INET6, sin6_port=htons(8080), ...}, 28) = 0
write(1, "Bound to [::]:8080\n", 19)    = 19
listen(3, 1)                            = 0
write(1, "Listening for connections...\n", 29) = 29
exit(0)                                 = ?
```

### 🏋️ Try it yourself

1. **Change the backlog** — Try `BACKLOG` values of 0, 1, 10, 128. Does the
   behavior change? (For this simple test, probably not visibly)

2. **Listen without binding** — Comment out the bind syscall. What error does
   listen return? (Hint: check strace for the return value)

3. **Extract the print function** — We created a `print` helper. Can you create
   an `exit_with_code` helper that takes the exit code in a register?

Commit:

```bash
jj commit -m "Add listen syscall (IPv6 dual-stack)"
```

### 🔎 You are here

- **You built**: a server socket that is actively listening on `[::]:8080` (IPv4
  and IPv6).
- **You learned**: how to factor out a tiny `print` helper and how `bl`/`ret`
  interact with the stack.
- **Next**: accept a client connection and start behaving like a real server.

---

## 6. Accept a Connection

Now we can accept incoming connections!

### 📚 Concepts to understand

| Concept            | Resource                                                                                                   | What you'll learn                        |
| ------------------ | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `accept()` syscall | [man 2 accept](https://man7.org/linux/man-pages/man2/accept.2.html)                                        | Accept connection, get new socket        |
| Blocking syscalls  | [Blocking vs Non-blocking I/O](https://www.ibm.com/docs/en/aix/7.2?topic=concepts-blocking-nonblocking-io) | accept() blocks until connection arrives |
| File descriptors   | [docs/research/file_descriptors.md](research/file_descriptors.md)                                          | FDs are handles to kernel objects        |

**The accept syscall:**

```c
int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
// ARM64 syscall number: 202
```

**Key insight:** `accept()` returns a **new** socket fd for the client
connection. The original socket continues listening for more connections.

```
Server socket (x19) ──listen──► accept() ──► Client socket (x20)
        │                           │
        │                           └── Use this to talk to client
        └── Still listening for more connections
```

**Arguments:**

| Register | Argument | Value           | Meaning                                  |
| -------- | -------- | --------------- | ---------------------------------------- |
| x0       | sockfd   | (server socket) | The listening socket                     |
| x1       | addr     | 0 (NULL)        | Where to store client address (optional) |
| x2       | addrlen  | 0 (NULL)        | Size of addr buffer (optional)           |
| x8       | syscall# | 202             | `accept`                                 |

### 6.1 Update `src/hello.s` to accept

We now add a new syscall and store a separate client socket:

```diff
// src/hello.s

 // Syscall numbers
 .equ SYS_BIND, 200
 .equ SYS_LISTEN, 201
+.equ SYS_ACCEPT, 202
+.equ SYS_CLOSE, 57

 // Server configuration
 .equ BACKLOG, 1
```

The full reference version at this step is:

```asm
// src/hello.s — Accept one connection (IPv6 dual-stack)

.equ STDOUT_FILENO, 1
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ SYS_CLOSE, 57
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202

.equ AF_INET6, 10
.equ SOCK_STREAM, 1
.equ PORT_BE, 0x901F
.equ BACKLOG, 1

.section .rodata
msg_socket:
    .ascii "Socket created\n"
msg_socket_len = . - msg_socket

msg_bind:
    .ascii "Bound to [::]:8080\n"
msg_bind_len = . - msg_bind

msg_listen:
    .ascii "Listening on http://localhost:8080\n"
msg_listen_len = . - msg_listen

msg_accept:
    .ascii "Connection accepted!\n"
msg_accept_len = . - msg_accept

msg_error:
    .ascii "Error occurred\n"
msg_error_len = . - msg_error

.section .data
// sockaddr_in6 structure (28 bytes)
sockaddr:
    .hword AF_INET6         // sin6_family (2 bytes)
    .hword PORT_BE          // sin6_port (2 bytes, big-endian)
    .word  0                // sin6_flowinfo (4 bytes)
    .fill  16, 1, 0         // sin6_addr = :: (16 bytes of zeros)
    .word  0                // sin6_scope_id (4 bytes)
sockaddr_len = . - sockaddr

.section .text
.global _start

_start:
    // === Create socket ===
    mov     x0, #AF_INET6
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_SOCKET
    svc     #0
    cmp     x0, #0
    b.lt    error
    mov     x19, x0             // x19 = server socket fd

    adr     x1, msg_socket
    mov     x2, #msg_socket_len
    bl      print

    // === Bind ===
    mov     x0, x19
    adr     x1, sockaddr
    mov     x2, #sockaddr_len
    mov     x8, #SYS_BIND
    svc     #0
    cmp     x0, #0
    b.lt    error

    adr     x1, msg_bind
    mov     x2, #msg_bind_len
    bl      print

    // === Listen ===
    mov     x0, x19
    mov     x1, #BACKLOG
    mov     x8, #SYS_LISTEN
    svc     #0
    cmp     x0, #0
    b.lt    error

    adr     x1, msg_listen
    mov     x2, #msg_listen_len
    bl      print

    // === Accept (blocks until connection) ===
    mov     x0, x19             // server socket
    mov     x1, #0              // NULL (don't need client addr)
    mov     x2, #0              // NULL
    mov     x8, #SYS_ACCEPT
    svc     #0
    cmp     x0, #0
    b.lt    error
    mov     x20, x0             // x20 = client socket fd

    adr     x1, msg_accept
    mov     x2, #msg_accept_len
    bl      print

    // Close client socket
    mov     x0, x20
    mov     x8, #SYS_CLOSE
    svc     #0

    b       exit_ok

print:
    stp     x29, x30, [sp, #-16]!
    mov     x0, #STDOUT_FILENO
    mov     x8, #SYS_WRITE
    svc     #0
    ldp     x29, x30, [sp], #16
    ret

error:
    adr     x1, msg_error
    mov     x2, #msg_error_len
    bl      print
exit_err:
    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0

exit_ok:
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0
```

### 6.2 Test it interactively

Update your justfile to expose port 8080:

```just
# Run the server with port exposed
run-server: build
    docker run --rm -it --platform linux/arm64 \
        -p 8080:8080 \
        -v "$(pwd)":/src drift-dev \
        ./build/drift

# Run server with strace
strace-server: build
    docker run --rm -it --platform linux/arm64 \
        -p 8080:8080 \
        -v "$(pwd)":/src drift-dev \
        strace -f ./build/drift
```

Now test:

```bash
# Terminal 1: Start server
just run-server

# Terminal 2: Connect with curl
curl http://localhost:8080/
```

You should see "Connection accepted!" in Terminal 1. Curl will hang because we
haven't sent a response yet (that's next!).

> **⚠️ Troubleshooting:** If you restart the server and see
> `bind: Address already in use` (or `Error occurred`), this is normal! The port
> is stuck in `TIME_WAIT`. You can wait 60 seconds, or **jump ahead to Section
> 8** to implement `SO_REUSEADDR` for an immediate fix.

### 🔍 Watch accept with strace

Run `just strace-server` in Terminal 1, then curl in Terminal 2:

```text
socket(AF_INET6, SOCK_STREAM, IPPROTO_IP) = 3
bind(3, {sa_family=AF_INET6, sin6_port=htons(8080), ...}, 28) = 0
listen(3, 1)                            = 0
write(1, "Listening on http://localhost:8080\n", 35) = 35
accept(3, NULL, NULL                    <-- blocks here, waiting...
                                        ...until curl connects...
accept(3, NULL, NULL)                   = 4   <-- new fd for client!
write(1, "Connection accepted!\n", 21) = 21
close(4)                                = 0
exit(0)                                 = ?
```

### 🏋️ Try it yourself

1. **Connect with netcat** — Try `nc localhost 8080` instead of curl. Type
   something and press Enter. What happens?

2. **Multiple connections** — Start the server, connect with curl, then quickly
   try another curl. Does the second one work? Why or why not?

3. **Test IPv6** — Try `curl http://[::1]:8080/` to connect via IPv6 loopback.
   Does it work?

4. **Get client address** — Modify the code to pass a sockaddr_in6 buffer to
   accept() instead of NULL. Can you print the client's IP?

For deeper background on Unix networking and systems programming (beyond this
walkthrough and Beej), see the networking and OS recommendations in
[`docs/research/books.md`](research/books.md).

Commit:

```bash
jj commit -m "Add accept syscall - server accepts connections (IPv6 dual-stack)"
```

### 🔎 You are here

- **You built**: a server that accepts a single TCP connection (IPv4 or IPv6)
  and then exits.
- **You learned**: how blocking syscalls behave and how to manage a separate
  client socket fd.
- **Next**: actually read the HTTP request and send a proper HTTP response.

---

## 7. Read Request and Send HTTP Response

Now the exciting part: handle the HTTP request and send a real response!

### 📚 Concepts to understand

| Concept             | Resource                                                                          | What you'll learn                |
| ------------------- | --------------------------------------------------------------------------------- | -------------------------------- |
| HTTP/1.1 protocol   | [RFC 9110 - HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html)          | Request/response format          |
| HTTP message format | [MDN - HTTP Messages](https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages) | Headers, body, CRLF line endings |
| `read()` syscall    | [man 2 read](https://man7.org/linux/man-pages/man2/read.2.html)                   | Read data from file descriptor   |
| `.bss` section      | [docs/research/constants_and_sections.md](research/constants_and_sections.md)     | Uninitialized data (for buffers) |

**HTTP request format (what the client sends):**

```http
GET / HTTP/1.1\r\n
Host: localhost:8080\r\n
User-Agent: curl/8.0\r\n
\r\n
```

**HTTP response format (what we send back):**

```http
HTTP/1.1 200 OK\r\n
Content-Type: text/plain\r\n
Content-Length: 27\r\n
Connection: close\r\n
\r\n
Hello from Drift on ARM64!
```

**Key points:**

- Lines end with `\r\n` (CRLF), not just `\n`
- Headers and body separated by blank line (`\r\n\r\n`)
- `Content-Length` must match body size exactly
- `Connection: close` tells client we'll close after response

**The read/write syscalls:**

```c
ssize_t read(int fd, void *buf, size_t count);   // syscall 63
ssize_t write(int fd, const void *buf, size_t count);  // syscall 64
```

### 7.1 Full HTTP server: `src/hello.s`

This is the biggest jump so far; conceptually, we:

- Add `read()` so we can consume an HTTP request.
- Introduce a `.bss` buffer for the incoming request.
- Build a complete HTTP response string in `.rodata`.
- Wrap everything in an `accept_loop` so the server can handle multiple
  connections.

If you want to skim, you can focus on the new `.bss` buffer, the `accept_loop`
label, and the `read`/`write` calls.

```asm
// src/hello.s — Minimal HTTP server (IPv6 dual-stack)

.equ STDOUT_FILENO, 1
.equ SYS_READ, 63
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ SYS_CLOSE, 57
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202

.equ AF_INET6, 10
.equ SOCK_STREAM, 1
.equ PORT_BE, 0x901F        // 8080 big-endian
.equ BACKLOG, 10

.section .rodata
msg_listen:
    .ascii "Drift listening on http://localhost:8080\n"
msg_listen_len = . - msg_listen

msg_error:
    .ascii "Error\n"
msg_error_len = . - msg_error

// HTTP response
http_response:
    .ascii "HTTP/1.1 200 OK\r\n"
    .ascii "Content-Type: text/plain\r\n"
    .ascii "Content-Length: 27\r\n"
    .ascii "Connection: close\r\n"
    .ascii "\r\n"
    .ascii "Hello from Drift on ARM64!"
http_response_len = . - http_response

.section .data
// sockaddr_in6 structure (28 bytes)
sockaddr:
    .hword AF_INET6         // sin6_family (2 bytes)
    .hword PORT_BE          // sin6_port (2 bytes, big-endian)
    .word  0                // sin6_flowinfo (4 bytes)
    .fill  16, 1, 0         // sin6_addr = :: (16 bytes of zeros)
    .word  0                // sin6_scope_id (4 bytes)
sockaddr_len = . - sockaddr

.section .bss
    .lcomm request_buf, 1024    // Buffer to read request into

.section .text
.global _start

_start:
    // === Create socket ===
    mov     x0, #AF_INET6
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_SOCKET
    svc     #0
    cmp     x0, #0
    b.lt    error
    mov     x19, x0             // x19 = server socket fd

    // === Bind ===
    mov     x0, x19
    adr     x1, sockaddr
    mov     x2, #sockaddr_len
    mov     x8, #SYS_BIND
    svc     #0
    cmp     x0, #0
    b.lt    error

    // === Listen ===
    mov     x0, x19
    mov     x1, #BACKLOG
    mov     x8, #SYS_LISTEN
    svc     #0
    cmp     x0, #0
    b.lt    error

    // Print startup message
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_listen
    mov     x2, #msg_listen_len
    mov     x8, #SYS_WRITE
    svc     #0

accept_loop:
    // === Accept connection ===
    mov     x0, x19             // server socket
    mov     x1, #0
    mov     x2, #0
    mov     x8, #SYS_ACCEPT
    svc     #0
    cmp     x0, #0
    b.lt    accept_loop         // retry on error
    mov     x20, x0             // x20 = client socket fd

    // === Read request (we don't parse it, just consume it) ===
    mov     x0, x20
    adr     x1, request_buf
    mov     x2, #1024
    mov     x8, #SYS_READ
    svc     #0
    // Ignore read errors/size, just proceed to respond

    // === Send HTTP response ===
    mov     x0, x20
    adr     x1, http_response
    mov     x2, #http_response_len
    mov     x8, #SYS_WRITE
    svc     #0

    // === Close client socket ===
    mov     x0, x20
    mov     x8, #SYS_CLOSE
    svc     #0

    // Loop back to accept next connection
    b       accept_loop

error:
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_error
    mov     x2, #msg_error_len
    mov     x8, #SYS_WRITE
    svc     #0

    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0
```

**New concepts:**

| Concept                          | Explanation                                                                   |
| -------------------------------- | ----------------------------------------------------------------------------- |
| `.lcomm request_buf, 1024`       | Allocate 1024 bytes in `.bss` section (uninitialized, zero-filled at runtime) |
| `accept_loop:` / `b accept_loop` | Infinite loop — server handles requests forever                               |
| Reading but ignoring             | We read to consume the request but don't parse it (yet)                       |

#### Robustness: what we intentionally skip here

- We assume `write` sends the full buffer in one call (no short writes).
- We ignore the return values from `read`/`write` except to keep going;
  production servers would loop until all bytes are processed or fail with a
  clear error.
- We don't handle malformed HTTP, partial requests, or slow clients.

Keeping the server simple and tiny makes it easier to reason about the core
syscalls; for more on debugging and hardening, see
[`docs/research/debugging.md`](research/debugging.md) and the Linux man-pages
linked above.

### 7.2 Test it!

```bash
# Terminal 1: Start server
just run-server

# Terminal 2: Test with curl
curl -v http://localhost:8080/
```

You should see:

```text
< HTTP/1.1 200 OK
< Content-Type: text/plain
< Content-Length: 27
< Connection: close
<
Hello from Drift on ARM64!
```

🎉 **You now have a working HTTP web server written in pure ARM64 assembly!**

Open http://localhost:8080 in a browser to see it work!

### 🔬 Inspect your web server binary

```bash
just inspect
```

Your complete HTTP server is still tiny — likely under **2KB**!

For more on how this binary is laid out on disk and in memory, see
[`docs/research/elf_format.md`](research/elf_format.md).

### 🔍 Watch the full request/response cycle

```bash
just strace-server
```

Then curl in another terminal:

```text
...
accept(3, NULL, NULL)                   = 4
read(4, "GET / HTTP/1.1\r\nHost: localhost:8080\r\nUser-Agent: curl/8.4.0\r\n...", 1024) = 78
write(4, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n...", content_length) = ...
close(4)                                = 0
accept(3, NULL, NULL                    <-- waiting for next connection
```

You can see exactly what curl sent and what your server responded!

### 🏋️ Try it yourself

1. **Change the response body** — Update the message. Don't forget to update
   `Content-Length` to match!

2. **Return HTML** — Change `Content-Type` to `text/html` and return
   `<h1>Hello from Drift!</h1>`. View it in a browser.

3. **Add a custom header** — Add `X-Powered-By: ARM64-Assembly\r\n` to the
   response. Verify with `curl -v`.

4. **Return a 404** — Change `200 OK` to `404 Not Found` and update the body.
   Does curl show the error?

5. **Break it on purpose** — Remove the `\r\n\r\n` separator between headers and
   body. What does curl show?

Commit:

```bash
jj commit -m "Complete HTTP server - reads request, sends response"
```

### 🔎 You are here

- **You built**: a looping HTTP/1.1 server in pure ARM64 assembly that responds
  to real clients.
- **You learned**: how to combine sockets, I/O, and HTTP framing into a tiny but
  complete server binary.
- **Next**: smooth over operational issues like quick restarts with
  `SO_REUSEADDR`.

---

## 8. Polish: SO_REUSEADDR, IPV6_V6ONLY, and Graceful Cleanup

Two common issues to fix:

1. **Quick restarts fail**: If you restart the server quickly, bind may fail
   with "Address already in use". Fix: `SO_REUSEADDR`.
2. **Dual-stack needs explicit opt-in on some systems**: While Linux usually
   enables dual-stack by default, we explicitly set `IPV6_V6ONLY=0` to be sure.

### 📚 Concepts to understand

| Concept                | Resource                                                                          | What you'll learn                   |
| ---------------------- | --------------------------------------------------------------------------------- | ----------------------------------- |
| `setsockopt()` syscall | [man 2 setsockopt](https://man7.org/linux/man-pages/man2/setsockopt.2.html)       | Set socket options                  |
| `SO_REUSEADDR`         | [man 7 socket](https://man7.org/linux/man-pages/man7/socket.7.html)               | Allow reuse of local addresses      |
| `IPV6_V6ONLY`          | [man 7 ipv6](https://man7.org/linux/man-pages/man7/ipv6.7.html)                   | Control IPv4-mapped IPv6 addresses  |
| TIME_WAIT state        | [TCP TIME_WAIT](https://vincent.bernat.ch/en/blog/2014-tcp-time-wait-state-linux) | Why ports stay "in use" after close |

**Why SO_REUSEADDR?**

When you close a TCP connection, the port enters TIME_WAIT state for ~60 seconds
to handle any delayed packets. During this time, `bind()` fails with EADDRINUSE.
`SO_REUSEADDR` tells the kernel "let me bind even if the port is in TIME_WAIT."

**Why IPV6_V6ONLY=0?**

By default on most Linux systems, an IPv6 socket can accept both IPv6 and
IPv4-mapped connections (dual-stack). Setting `IPV6_V6ONLY=0` explicitly ensures
this behavior, making the server portable across different configurations.

**The setsockopt syscall:**

```c
int setsockopt(int sockfd, int level, int optname, 
               const void *optval, socklen_t optlen);
// ARM64 syscall number: 208
```

### 8.1 Updated `src/hello.s` with socket options

Here we call `setsockopt()` twice before `bind()`:

1. `IPV6_V6ONLY=0` — enable dual-stack (accept IPv4 and IPv6)
2. `SO_REUSEADDR=1` — allow quick restarts

```diff
// src/hello.s

 // Syscall numbers
 .equ SYS_ACCEPT, 202
+.equ SYS_SETSOCKOPT, 208

 // Socket options
+.equ SOL_SOCKET, 1
+.equ SO_REUSEADDR, 2
+.equ IPPROTO_IPV6, 41
+.equ IPV6_V6ONLY, 26
```

The full reference version at this step is:

```asm
// src/hello.s — HTTP server with SO_REUSEADDR and IPV6_V6ONLY (IPv6 dual-stack)

.equ STDOUT_FILENO, 1
.equ SYS_READ, 63
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ SYS_CLOSE, 57
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202
.equ SYS_SETSOCKOPT, 208

.equ AF_INET6, 10
.equ SOCK_STREAM, 1
.equ SOL_SOCKET, 1
.equ SO_REUSEADDR, 2
.equ IPPROTO_IPV6, 41
.equ IPV6_V6ONLY, 26
.equ PORT_BE, 0x901F        // 8080 big-endian
.equ BACKLOG, 10

.section .rodata
msg_listen:
    .ascii "Drift listening on http://localhost:8080\n"
msg_listen_len = . - msg_listen

msg_error:
    .ascii "Error\n"
msg_error_len = . - msg_error

http_response:
    .ascii "HTTP/1.1 200 OK\r\n"
    .ascii "Content-Type: text/plain\r\n"
    .ascii "Content-Length: 27\r\n"
    .ascii "Connection: close\r\n"
    .ascii "\r\n"
    .ascii "Hello from Drift on ARM64!"
http_response_len = . - http_response

.section .data
// sockaddr_in6 structure (28 bytes)
sockaddr:
    .hword AF_INET6         // sin6_family (2 bytes)
    .hword PORT_BE          // sin6_port (2 bytes, big-endian)
    .word  0                // sin6_flowinfo (4 bytes)
    .fill  16, 1, 0         // sin6_addr = :: (16 bytes of zeros)
    .word  0                // sin6_scope_id (4 bytes)
sockaddr_len = . - sockaddr

// Socket option values
optval_zero:
    .word 0                 // For IPV6_V6ONLY = 0 (enable dual-stack)
optval_one:
    .word 1                 // For SO_REUSEADDR = 1
optval_len = 4

.section .bss
    .lcomm request_buf, 1024

.section .text
.global _start

_start:
    // === Create socket ===
    mov     x0, #AF_INET6
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_SOCKET
    svc     #0
    cmp     x0, #0
    b.lt    error
    mov     x19, x0

    // === Set IPV6_V6ONLY = 0 (enable dual-stack: accept IPv4 and IPv6) ===
    mov     x0, x19
    mov     x1, #IPPROTO_IPV6
    mov     x2, #IPV6_V6ONLY
    adr     x3, optval_zero
    mov     x4, #optval_len
    mov     x8, #SYS_SETSOCKOPT
    svc     #0
    // Ignore errors, proceed anyway

    // === Set SO_REUSEADDR = 1 (allow quick restarts) ===
    mov     x0, x19
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_REUSEADDR
    adr     x3, optval_one
    mov     x4, #optval_len
    mov     x8, #SYS_SETSOCKOPT
    svc     #0
    // Ignore errors, proceed anyway

    // === Bind ===
    mov     x0, x19
    adr     x1, sockaddr
    mov     x2, #sockaddr_len
    mov     x8, #SYS_BIND
    svc     #0
    cmp     x0, #0
    b.lt    error

    // === Listen ===
    mov     x0, x19
    mov     x1, #BACKLOG
    mov     x8, #SYS_LISTEN
    svc     #0
    cmp     x0, #0
    b.lt    error

    // Print startup message
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_listen
    mov     x2, #msg_listen_len
    mov     x8, #SYS_WRITE
    svc     #0

accept_loop:
    mov     x0, x19
    mov     x1, #0
    mov     x2, #0
    mov     x8, #SYS_ACCEPT
    svc     #0
    cmp     x0, #0
    b.lt    accept_loop
    mov     x20, x0

    // Read request
    mov     x0, x20
    adr     x1, request_buf
    mov     x2, #1024
    mov     x8, #SYS_READ
    svc     #0

    // Send response
    mov     x0, x20
    adr     x1, http_response
    mov     x2, #http_response_len
    mov     x8, #SYS_WRITE
    svc     #0

    // Close client
    mov     x0, x20
    mov     x8, #SYS_CLOSE
    svc     #0

    b       accept_loop

error:
    mov     x0, #STDOUT_FILENO
    adr     x1, msg_error
    mov     x2, #msg_error_len
    mov     x8, #SYS_WRITE
    svc     #0

    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0
```

Now you can restart the server immediately without waiting for TIME_WAIT!

#### Robustness: socket options tradeoffs

- We ignore `setsockopt` errors for simplicity; a hardened server would log and
  abort if critical options fail.
- We don't handle graceful shutdown (signals, draining connections); Ctrl+C just
  terminates the process and lets the kernel reclaim resources.
- We still assume simple, short-lived connections; long-lived production servers
  typically track connection state and health more carefully.

### 🔍 Verify socket options in strace

```bash
just strace-server
```

```text
socket(AF_INET6, SOCK_STREAM, IPPROTO_IP) = 3
setsockopt(3, SOL_IPV6, IPV6_V6ONLY, [0], 4) = 0
setsockopt(3, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
bind(3, {sa_family=AF_INET6, sin6_port=htons(8080), ...}, 28) = 0
...
```

You can see both socket options being set before bind!

### 🏋️ Try it yourself

1. **Test quick restarts** — Start the server, curl it, Ctrl+C, immediately
   restart. Does it work now?

2. **Remove SO_REUSEADDR** — Comment it out and try the quick restart test. What
   error do you see?

3. **Test dual-stack** — With the server running, try both:
   - `curl http://127.0.0.1:8080/` (IPv4)
   - `curl http://[::1]:8080/` (IPv6) Both should work!

4. **Disable dual-stack** — Change `optval_zero` to `optval_one` for
   `IPV6_V6ONLY`. Now try `curl http://127.0.0.1:8080/`. What happens?

Commit:

```bash
jj commit -m "Add SO_REUSEADDR and IPV6_V6ONLY for dual-stack support"
```

### 🔎 You are here

- **You built**: a dual-stack (IPv4 + IPv6) HTTP server that survives quick
  restarts on the same port.
- **You learned**: how to tweak socket options with `setsockopt` to solve common
  operational issues and enable dual-stack networking.
- **Next**: package this binary into an ARM64 Docker image and ship it.

---

## 🎓 Part A Complete!

You now have a **working HTTP web server in pure ARM64 assembly**. Let's recap
the syscalls you learned:

| Syscall      | Number | Purpose                         |
| ------------ | ------ | ------------------------------- |
| `socket`     | 198    | Create communication endpoint   |
| `setsockopt` | 208    | Set socket options              |
| `bind`       | 200    | Assign address to socket        |
| `listen`     | 201    | Mark socket as passive (server) |
| `accept`     | 202    | Accept incoming connection      |
| `read`       | 63     | Read data from file descriptor  |
| `write`      | 64     | Write data to file descriptor   |
| `close`      | 57     | Close file descriptor           |
| `exit`       | 93     | Terminate process               |

### 🔬 Final binary inspection

```bash
just inspect
```

Appreciate what you built:

- A complete HTTP server in **~2KB**
- No libc, no runtime, no dependencies
- Just your code talking directly to the Linux kernel
- Every byte serves a purpose

**Further learning:**

- [Beej's Guide to Network Programming](https://beej.us/guide/bgnet/) — The
  classic socket programming guide
- [ARM Architecture Reference Manual](https://developer.arm.com/documentation/ddi0487/latest)
  — Official ARM64 instruction reference
- [Linux man-pages](https://man7.org/linux/man-pages/) — Definitive syscall
  documentation
- [docs/research/debugging.md](research/debugging.md) — How to debug your
  assembly with LLDB

---

# Part B: Packaging & Deployment

Now that we have a working web server, let's package and deploy it!

---

## 9. Dockerfile for Drift (ARM64 Image)

Create `Dockerfile` in the project root:

```dockerfile
# syntax=docker/dockerfile:1.7

#########################
# Build stage
#########################
FROM --platform=linux/arm64 ubuntu:24.04 AS build

RUN apt-get update && \
    apt-get install -y clang lld && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY src/ src/

RUN mkdir -p build && \
    clang --target=aarch64-linux-gnu -nostdlib \
      -Wl,-e,_start -Wl,--gc-sections \
      -o build/drift src/hello.s

#########################
# Runtime stage
#########################
FROM --platform=linux/arm64 ubuntu:24.04

RUN useradd -m drift && mkdir -p /opt/drift && chown drift:drift /opt/drift

WORKDIR /opt/drift
COPY --from=build /src/build/drift /opt/drift/drift

USER drift
EXPOSE 8080

CMD ["/opt/drift/drift"]
```

Update `justfile` with image build recipes:

```just
# justfile — Drift build recipes

default: help

help:
    @echo "Drift — ARM64 Assembly Web Server"
    @echo ""
    @echo "Development:"
    @echo "  just build          - Build the binary"
    @echo "  just run            - Build and run (stdout test)"
    @echo "  just run-server     - Run as HTTP server on port 8080"
    @echo "  just strace         - Run with strace to see syscalls"
    @echo "  just strace-server  - Run server with strace"
    @echo "  just inspect        - Inspect the binary"
    @echo "  just shell          - Open shell in dev container"
    @echo ""
    @echo "Packaging:"
    @echo "  just build-image    - Build production Docker image"
    @echo "  just push-image     - Push image to GHCR"
    @echo ""

# Registry config (update with your username)
REGISTRY := "ghcr.io"
IMAGE_NS := "your-github-username"
IMAGE_NAME := "drift"
IMAGE := REGISTRY + "/" + IMAGE_NS + "/" + IMAGE_NAME
VERSION := env_var_or_default("VERSION", "dev")

# Build dev container
build-dev:
    docker build --platform linux/arm64 -f Dockerfile.dev -t drift-dev .

# Build binary
build: build-dev
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        sh -c 'mkdir -p build && clang --target=aarch64-linux-gnu -nostdlib \
            -Wl,-e,_start -Wl,--gc-sections \
            -o build/drift src/hello.s'

# Run binary (stdout test)
run: build
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        ./build/drift

# Run as HTTP server
run-server: build
    docker run --rm -it --platform linux/arm64 \
        -p 8080:8080 \
        -v "$(pwd)":/src drift-dev \
        ./build/drift

# Run with strace
strace: build
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        strace -f ./build/drift

# Run server with strace
strace-server: build
    docker run --rm -it --platform linux/arm64 \
        -p 8080:8080 \
        -v "$(pwd)":/src drift-dev \
        strace -f ./build/drift

# Inspect binary
inspect: build
    @echo "=== File type and size ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        sh -c 'file build/drift && ls -lh build/drift'
    @echo ""
    @echo "=== Section headers ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        readelf -S build/drift
    @echo ""
    @echo "=== Symbol table ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        nm build/drift
    @echo ""
    @echo "=== Disassembly ==="
    docker run --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        objdump -d build/drift

# Interactive shell
shell: build-dev
    docker run -it --rm --platform linux/arm64 \
        -v "$(pwd)":/src drift-dev \
        /bin/bash

# Build production image
build-image:
    docker buildx build \
        --platform linux/arm64 \
        -t {{IMAGE}}:{{VERSION}} \
        -t {{IMAGE}}:latest \
        --load \
        .

# Run production image locally
run-image: build-image
    docker run --rm -it -p 8080:8080 {{IMAGE}}:{{VERSION}}

# Push to GHCR
push-image: build-image
    docker push {{IMAGE}}:{{VERSION}}
    docker push {{IMAGE}}:latest

# Deployment host (update with your VM IP)
DRIFT_HOST := "ubuntu@your-drift-vm-ip"

# Deploy to VM
deploy:
    just push-image
    ssh {{DRIFT_HOST}} ' \
        sudo docker pull {{IMAGE}}:{{VERSION}} && \
        sudo docker tag {{IMAGE}}:{{VERSION}} {{IMAGE}}:latest && \
        (sudo docker stop drift || true) && \
        (sudo docker rm drift || true) && \
        sudo docker run -d --name drift -p 80:8080 --restart unless-stopped {{IMAGE}}:latest \
    '
```

Test the production image:

```bash
just run-image
# Then: curl http://localhost:8080/
```

For more depth on container images and multi-stage builds, see:

- **Dockerfile reference**:
  [`https://docs.docker.com/engine/reference/builder/`](https://docs.docker.com/engine/reference/builder/)
- **Docker Buildx and multi-platform images**:
  [`https://docs.docker.com/build/buildx/`](https://docs.docker.com/build/buildx/)

Commit:

```bash
jj commit -m "Add production Dockerfile and image build recipes"
```

### 🔎 You are here

- **You built**: an ARM64-only multi-stage Docker image that compiles and runs
  your Drift server.
- **You learned**: how to separate dev and runtime images and how to drive image
  builds via `just`.
- **Next**: push that image to GitHub Container Registry so OCI can pull it.

---

## 10. GitHub Container Registry (GHCR) Setup

1. Ensure your repo is on GitHub.
2. Create a Personal Access Token with `write:packages` scope.
3. Log in to GHCR:

```bash
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u your-github-username --password-stdin
```

4. Update `IMAGE_NS` in justfile with your GitHub username.

5. Push your first image:

```bash
VERSION=v0.1.0 just push-image
```

Your image is now at: `ghcr.io/your-github-username/drift:v0.1.0`

For more on GitHub Container Registry capabilities and permissions, see:

- **GitHub Docs – About GitHub Container Registry**:
  [`https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry`](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

Commit:

```bash
jj commit -m "Configure GHCR image push"
```

### 🔎 You are here

- **You built**: a workflow to tag and push versioned Docker images of Drift to
  GHCR.
- **You learned**: how to authenticate Docker to GHCR and parameterize image
  names with `just`.
- **Next**: create OCI infrastructure that can run those images.

---

## 11. OCI Infrastructure with Packer + Terraform

### 11.1 Create OCI Free Tier account

1. Go to https://www.oracle.com/cloud/free/
2. Sign up, select home region, verify payment method
3. Ensure access to **Always Free** Ampere A1 shapes

### 11.2 Packer: Base image with Docker

Create `packer/oci.pkr.hcl`:

```hcl
packer {
  required_plugins {
    oracle = {
      source  = "github.com/hashicorp/oracle"
      version = ">= 1.1.0"
    }
  }
}

variable "compartment_ocid" {}
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" {}
variable "subnet_ocid" {}
variable "base_image_ocid" {
  description = "OCID of Ubuntu ARM64 base image"
}

source "oracle-oci" "drift-base" {
  compartment_ocid = var.compartment_ocid
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_file = var.private_key_path
  region           = var.region
  base_image_ocid  = var.base_image_ocid
  shape            = "VM.Standard.A1.Flex"
  subnet_ocid      = var.subnet_ocid
  ssh_username     = "ubuntu"
}

build {
  name    = "drift-base-image"
  sources = ["source.oracle-oci.drift-base"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
  }
}
```

Build the base image:

```bash
cd packer
packer init oci.pkr.hcl
packer build -var 'compartment_ocid=...' ... oci.pkr.hcl
```

For more on these tooling pieces:

- **Packer oracle-oci plugin docs**:
  [`https://developer.hashicorp.com/packer/plugins/builders/oracle/oci`](https://developer.hashicorp.com/packer/plugins/builders/oracle/oci)
- **Terraform `oracle/oci` provider docs**:
  [`https://registry.terraform.io/providers/oracle/oci/latest/docs`](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- **OCI networking and Ampere A1 shapes**: Oracle Cloud docs linked from the
  Always Free page and the OCI networking guides.

### 11.3 Terraform: Network + VM

Create `terraform/main.tf`:

```hcl
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" {}
variable "compartment_ocid" {}
variable "availability_domain" {}
variable "drift_image_ocid" {}

# VCN
resource "oci_core_vcn" "drift_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "drift-vcn"
  cidr_block     = "10.0.0.0/16"
}

# Internet Gateway
resource "oci_core_internet_gateway" "drift_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.drift_vcn.id
  display_name   = "drift-igw"
}

# Route Table
resource "oci_core_route_table" "drift_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.drift_vcn.id
  display_name   = "drift-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.drift_igw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List
resource "oci_core_security_list" "drift_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.drift_vcn.id
  display_name   = "drift-security-list"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # HTTP
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      destination_port_range {
        min = 80
        max = 80
      }
    }
  }

  # SSH
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      destination_port_range {
        min = 22
        max = 22
      }
    }
  }
}

# Subnet
resource "oci_core_subnet" "drift_subnet" {
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.drift_vcn.id
  display_name        = "drift-subnet"
  cidr_block          = "10.0.1.0/24"
  route_table_id      = oci_core_route_table.drift_rt.id
  dns_label           = "driftsubnet"
  security_list_ids   = [oci_core_security_list.drift_sl.id]
}

# VM Instance
resource "oci_core_instance" "drift" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "drift-server"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 2
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.drift_subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = var.drift_image_ocid
  }

  metadata = {
    ssh_authorized_keys = file("~/.ssh/id_rsa.pub")
  }
}

output "drift_public_ip" {
  value = oci_core_instance.drift.public_ip
}
```

Apply:

```bash
cd terraform
terraform init
terraform apply -var 'tenancy_ocid=...' ...
```

Commit:

```bash
jj commit -m "Add Packer and Terraform for OCI infrastructure"
```

### 🔎 You are here

- **You built**: reproducible OCI network + VM infrastructure (VCN, subnet,
  security list, and an ARM VM image) using Packer and Terraform.
- **You learned**: how to describe OCI resources as code and bake a Docker-ready
  base image.
- **Next**: deploy the Drift image to that VM and verify it from the public
  internet.

---

## 12. Deploy and Go Live!

### 12.1 First deployment

1. Update `DRIFT_HOST` in justfile with your VM's public IP
2. SSH into VM and log into GHCR:

```bash
ssh ubuntu@<drift_public_ip>
sudo docker login ghcr.io -u your-github-username
```

3. Deploy:

```bash
VERSION=v0.1.0 just deploy
```

4. Test it:

```bash
curl http://<drift_public_ip>/
```

You should see:

```text
Hello from Drift on ARM64!
```

### 12.2 Iterate

Make changes, bump version, deploy:

```bash
# Edit src/hello.s (change the message!)
jj commit -m "Update greeting"
VERSION=v0.2.0 just deploy
```

### 🔎 You are here (end-to-end)

- **You built**: a pipeline from local ARM64 assembly all the way to a live HTTP
  endpoint on OCI.
- **You learned**: how each layer (syscalls, Docker, registry, infra) fits into
  the path from source to production.
- **Next**: iterate on features, harden robustness/security, or branch out into
  the “Next Steps & Ideas” section below.

---

## 🎉 Congratulations!

You now have:

- ✅ A **pure ARM64 assembly HTTP server**
- ✅ Supporting both **IPv4 and IPv6** (dual-stack)
- ✅ Built from scratch using only **Linux syscalls**
- ✅ Packaged as an **ARM64 Docker image**
- ✅ Hosted on **GitHub Container Registry**
- ✅ Running on an **OCI ARM64 VM** (Always Free!)
- ✅ Deployed with a single `just deploy` command

**Drift is live!** 🚀

---

## 📚 Quick Reference

### ARM64 Registers

| Register | Purpose                     | Preserved across calls? |
| -------- | --------------------------- | ----------------------- |
| x0-x7    | Arguments, return values    | No                      |
| x8       | Syscall number              | No                      |
| x9-x15   | Temporaries                 | No                      |
| x16-x17  | Intra-procedure call        | No                      |
| x19-x28  | Callee-saved                | **Yes**                 |
| x29      | Frame pointer               | **Yes**                 |
| x30      | Link register (return addr) | **Yes**                 |
| sp       | Stack pointer               | **Yes**                 |

### Common Assembly Directives

| Directive           | Purpose                        |
| ------------------- | ------------------------------ |
| `.equ NAME, VALUE`  | Define constant (no memory)    |
| `.section .text`    | Code section                   |
| `.section .rodata`  | Read-only data                 |
| `.section .data`    | Writable data                  |
| `.section .bss`     | Uninitialized data             |
| `.global SYMBOL`    | Export symbol                  |
| `.ascii "str"`      | String (no null terminator)    |
| `.asciz "str"`      | String (with null terminator)  |
| `.byte VALUE`       | 1 byte                         |
| `.hword VALUE`      | 2 bytes                        |
| `.word VALUE`       | 4 bytes                        |
| `.quad VALUE`       | 8 bytes                        |
| `.skip N`           | Reserve N bytes                |
| `.fill N, S, V`     | Fill N items of S bytes with V |
| `.lcomm NAME, SIZE` | Reserve SIZE bytes in .bss     |

### Socket Constants (IPv6 Dual-Stack)

| Constant       | Value | Purpose                          |
| -------------- | ----- | -------------------------------- |
| `AF_INET6`     | 10    | IPv6 address family              |
| `SOCK_STREAM`  | 1     | TCP socket type                  |
| `SOL_SOCKET`   | 1     | Socket-level options             |
| `SO_REUSEADDR` | 2     | Allow address reuse              |
| `IPPROTO_IPV6` | 41    | IPv6 protocol options            |
| `IPV6_V6ONLY`  | 26    | IPv6-only or dual-stack (0=dual) |

### sockaddr_in6 Structure (28 bytes)

```
Offset  Size  Field           Description
──────  ────  ─────────────   ─────────────────────────
0       2     sin6_family     AF_INET6 (10)
2       2     sin6_port       Port (big-endian)
4       4     sin6_flowinfo   Flow info (usually 0)
8       16    sin6_addr       IPv6 address (:: = all zeros)
24      4     sin6_scope_id   Scope ID (usually 0)
```

### Socket Syscalls (ARM64)

| Syscall    | Number | Signature                                            |
| ---------- | ------ | ---------------------------------------------------- |
| socket     | 198    | `socket(domain, type, protocol)`                     |
| bind       | 200    | `bind(sockfd, addr, addrlen)`                        |
| listen     | 201    | `listen(sockfd, backlog)`                            |
| accept     | 202    | `accept(sockfd, addr, addrlen)`                      |
| setsockopt | 208    | `setsockopt(sockfd, level, optname, optval, optlen)` |
| read       | 63     | `read(fd, buf, count)`                               |
| write      | 64     | `write(fd, buf, count)`                              |
| close      | 57     | `close(fd)`                                          |
| exit       | 93     | `exit(status)`                                       |

---

## Next Steps & Ideas

- **Parse HTTP requests**: Route different paths, handle methods
- **Serve files**: Read from filesystem, serve HTML/CSS/JS
- **Dynamic content**: Generate responses based on request data
- **Multiple source files**: Split into `socket.s`, `http.s`, `main.s`
- **Rust interop**: Call assembly from Rust, or vice versa
- **CI/CD**: GitHub Actions to build/push on tag
- **TLS**: Add HTTPS support (this would be ambitious!)

For a curated list of books and longer-form resources that complement this
walkthrough (covering ARM, Linux systems, networking, and infrastructure), see
[`docs/research/books.md`](research/books.md).
