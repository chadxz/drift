set unstable := true

IMAGE := "ghcr.io/chadxz/drift"
VERSION := `git rev-parse HEAD`
DEV_IMAGE := "drift-dev"

default:
  @just --list --justfile {{ justfile() }}

# Build ARM64 container image using Docker buildx
build-image:
    docker buildx build --platform linux/arm64 \
        -t {{ IMAGE }}:{{ VERSION }} \
        -t {{ IMAGE }}:latest \
        .

# Build assembly with LLVM tooling
build:
    mkdir -p build
    clang --target=aarch64-linux-gnu \
        -nostdlib \
        -Wl,--gc-sections \
        -o build/drift \
        src/hello.s

build-socket:
    mkdir -p build
    clang --target=aarch64-linux-gnu \
        -nostdlib \
        -Wl,--gc-sections \
        -o build/socket \
        src/socket.s

# Build assembly with debug symbols
build-debug:
    mkdir -p build
    clang --target=aarch64-linux-gnu \
        -nostdlib \
        -g \
        -Wl,--gc-sections \
        -o build/drift \
        src/hello.s

# Build development Docker image
build-dev:
    docker build --platform linux/arm64 \
        -f Dockerfile.dev -t {{ DEV_IMAGE }} .

# Run development container interactively (builds image if needed)
dev: build-dev
    docker run -it \
        -v $(pwd):/workspace \
        {{ DEV_IMAGE }}

# Run a command in the development container (builds image if needed)
dev-run cmd: build-dev
    docker run --rm \
        -v $(pwd):/workspace \
        {{ DEV_IMAGE }} \
        bash -c "{{ cmd }}"

# Run with strace to see syscalls
strace: build
  strace -f ./build/drift

# Start binary under lldb debugger (builds with debug symbols first)
debug: build-debug
    lldb build/drift

# Start binary under radare2 debugger (builds with debug symbols first)
debug-r2: build-debug
    r2 -d build/drift

# Format source files in the repository
format:
    mise exec -- dprint fmt

# Check formatting without modifying files
check-format:
    mise exec -- dprint check
