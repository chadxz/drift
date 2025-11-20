# 🎨 Project Canvas: **Drift** — ARM64 Assembly Web‑App Experiment

> Pure ARM64 assembly • Docker image • GitHub Container Registry (GHCR) • OCI
> ARM instance • Packer + Terraform

---

## 1. Vision & Constraints

**Goal**\
Build a small web‑server in **pure ARM64 assembly**, running on Linux, with a
modern developer experience on macOS:

- Every line of server logic is **assembly**
- Binary and container target **ARM64 Linux**
- Toolchain: **LLVM‑based** (`clang`, `lld`, `lldb`)
- Workflow uses:
  - Helix for editing
  - `just` as the command runner
  - Docker image packaged and published to GHCR
  - Deployment target: OCI Ampere A1 ARM64 VM (Always Free)
  - VM provisioning: Terraform
  - VM base image: built via Packer (includes Docker runtime)
  - Version control & release management: Jujutsu (jj) + GitHub + Releases

**Future nice‑to‑haves**

- Interop with Rust if we ever expand beyond pure assembly
- CI/CD pipeline: container image + binary artifact
- HTTP server expansion (accept → read → respond)
- Scaling and management features

---

## 2. Architecture Overview

### Runtime Target

- **CPU**: ARM64 / AArch64
- **OS**: Linux
- **Binary format**: ELF executable
- **Entry point**: `_start` (no CRT / libc)
- **Initial syscalls**: `write`, `exit`
- **Future HTTP‑server syscalls**: `socket`, `bind`, `listen`, `accept`, `read`,
  `send`, `close`

### Development Environment

- Host: macOS (Apple Silicon)
- Editor: Helix
- Task runner: `just`
- Container packaging: Docker (build ARM64 image)
- Registry: GitHub Container Registry (GHCR)
- Deployment target: OCI Arm Compute (Always Free)
- VM provisioning: Terraform + Packer
- Networking: VM exposed public IP + port 80, container listens on port 80

---

## 3. Tooling Stack

### 3.1 Core Tools

- **LLVM / Clang / LLD / LLDB**
  - Build ARM64 ELF: `clang --target=aarch64-linux-gnu ...`
  - Linker: `ld.lld`
  - Debugger: `lldb`
- **Docker + Container Image**
  - Build multi‑platform ARM64 image
  - Push to GHCR: `ghcr.io/<user>/drift:<tag>`
- **GitHub Container Registry (GHCR)**
  - Host container image versions
  - Use GitHub Releases to publish binary + image
- **Packer**
  - Build OCI ARM64 base image (Ubuntu + Docker runtime)
  - Rebuild only when base dependencies change
- **Terraform (OCI provider)**
  - Provision VCN, subnet, internet gateway, security list
  - Create ARM64 VM instance from custom image
- **Jujutsu (jj) + GitHub**
  - Local DVCS workflow with history rewriting
  - GitHub remote + Releases

### 3.2 Assembly & ABI

- Syntax: GAS/Clang‑style ARM64 assembly (`.section`, `.global _start`, etc.)
- Syscall convention:
  - `x0‑x5` = arguments
  - `x8` = syscall number
  - `svc #0` = syscall trap
- Key references:
  - [AArch64 architecture overview](https://en.wikipedia.org/wiki/AArch64)
  - [ARM64 Linux syscall table](https://syscalls.mebeim.net/?table=arm64/64/aarch64/v6.2)

---

## 4. Project Layout

```text
drift/
  src/
    hello.s           # pure ARM64 assembly entry‑point
  Dockerfile          # build ARM64 container image for server
  justfile            # build/push/deploy workflows
  packer/
    oci.pkr.hcl        # Packer template for base image (Ubuntu ARM64 + Docker)
  terraform/
    main.tf            # Terraform module + resources for VM + network
  .gitignore
  .jj/                # Jujutsu metadata
  README.md           # This canvas + project instructions
```

**Key workflows**

- Build binary + container image locally
- Push image to GHCR + create GitHub Release (binary + image)
- VM in OCI pulls new image and runs it (container listens on port 80)
- Provision VM once via Terraform + Packer, then app updates via container
  deploy

---

## 5. Milestones & Checklists

### Milestone 1 – Setup base infrastructure & registry

- [ ] Create GHCR repository: `ghcr.io/<user>/drift`
- [ ] Configure GitHub Releases for binary + image versioning
- [ ] Set up OCI account (Free Tier)
- [ ] Create Packer template `packer/oci.pkr.hcl` to build ARM64 base image with
      Docker runtime
- [ ] Create Terraform module `terraform/` to provision ARM64 VM using custom
      image
- [ ] Commit initial setup via jj

### Milestone 2 – Build & publish container image

- [ ] Write `Dockerfile` for ARM64: build stage (LLVM) + runtime stage
- [ ] Add `justfile` recipes: `build-image`, `push-image`, `deploy`
- [ ] Locally build/push image to GHCR with tags (e.g., `v0.1.0`, `latest`)
- [ ] Create GitHub Release `v0.1.0` including binary for ARM64
- [ ] Test container locally or on VM: image listens on port 80

### Milestone 3 – Deploy to OCI VM

- [ ] Provision VM via Terraform (once)
- [ ] SSH into VM, verify Docker installed and can run:
  ```bash
  docker run --rm -p 80:80 ghcr.io/<user>/drift:latest
  ```
- [ ] Configure VM public IP + security list to allow TCP port 80 from
      `0.0.0.0/0`
- [ ] In `justfile` add deploy recipe: push image + ssh + pull + restart
      container
- [ ] Trigger `just deploy VERSION=v0.1.0` and verify public IP returns your app

### Milestone 4 – Maintenance & future proofing

- [ ] Establish tag strategy & rollback plan (version tags + `latest`)
- [ ] Clean up old images in GHCR (retention policy)
- [ ] Document how/when to rebuild Packer image (base OS update, Docker version,
      etc.)
- [ ] Outline next steps: HTTP server logic, Rust interop, scaling,
      observability

---

## 6. Walk‑through: Setting Up Your OCI Free Tier Account

1. Navigate to the [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
   page.
2. Click **“Start for free”** and complete signup. Provide required details;
   you’ll get access to Always Free + initial trial credits.
3. Select your **Home Region** carefully (Always Free resources must be created
   in your home region).
4. Confirm Always Free entitlement for Arm‑based compute.
5. Create a **Compartment** (e.g., `drift‑project`) in the OCI Console.
6. (Later) When using Terraform, set provider credentials and use the Arm shape
   (`VM.Standard.A1.Flex`) for your VM.
7. Make sure VM has **public IP** and that security list/NSG allows ingress on
   **TCP port 80** from `0.0.0.0/0`.
8. Install Docker on the VM after provisioning (or bake it via Packer):
   ```bash
   sudo apt-get update
   sudo apt-get install -y docker.io
   sudo systemctl enable docker
   sudo systemctl start docker
   ```
9. Test the VM:
   ```bash
   docker run --rm -p 80:80 ghcr.io/<user>/drift:latest
   ```
10. Document SSH key setup and verify you can `ssh` into your VM using keypair
    created at provisioning.

---

## 7. Resources & Links

- Oracle Cloud Free Tier: https://www.oracle.com/cloud/free/
- GitHub Container Registry docs:
  https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- AArch64 architecture overview: https://en.wikipedia.org/wiki/AArch64
- ARM64 Linux syscall table:
  https://syscalls.mebeim.net/?table=arm64/64/aarch64/v6.2

---

## 8. Notes / Scratchpad

- Use semantic tag strategy: `vX.Y.Z` + `latest` for your container/binary
- Binary distribution: include `drift‑linux‑arm64` (and possibly
  `drift‑linux‑amd64` later) in GitHub Release
- Keep Packer image rebuilds minimal (only when base OS or runtime changes)
- Ensure your build/push pipelines target ARM64 (`--platform linux/arm64`)
- Monitor VM usage to stay within Always Free limits.

---
