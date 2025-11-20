# Drift: End-to-End Walkthrough

> From first `hello world` in ARM64 assembly to deployment on OCI using Docker,
> GHCR, Packer, and Terraform.

This walkthrough takes you **from zero to a deployed Drift instance**:

- Local ARM64 assembly **hello world**
- Packaged as an **ARM64 Docker image**
- Pushed to **GitHub Container Registry (GHCR)**
- Deployed on an **Oracle Cloud Infrastructure (OCI) ARM (Ampere A1) VM**
- VM provisioned with **Packer + Terraform**
- Container served publicly on **port 80**

Assumptions:

- Host: macOS on Apple Silicon
- You’re comfortable with: shell, Git/GitHub, Docker, jj, Helix
- You have or will create: GitHub account, OCI Free Tier account

---

## 0. High-Level Architecture

1. **Code**: Drift is an ARM64 Linux ELF binary, written in **AArch64 (ARM64)
   GAS/Clang-style assembly**.
2. **Local dev**:
   - Build using `clang --target=aarch64-linux-gnu`
   - Wrap commands with `just`
   - Optionally run in a local ARM64 Linux Docker container
3. **Packaging**:
   - Build an ARM64 Docker image for Drift
   - Push to GitHub Container Registry (GHCR)
4. **Infra**:
   - Use **Packer** to create an ARM64 OCI base image:
     - Ubuntu (ARM64)
     - Docker installed and enabled
   - Use **Terraform** to:
     - Create VCN, subnet, internet gateway, security rules
     - Create VM instance from the Packer image (Ampere A1)
5. **Deployment**:
   - On deploy:
     - Build + push new Docker image to GHCR
     - SSH into VM, `docker pull`, restart container
   - Container exposes port 80, VM allows public access on port 80.

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

Commit:

```bash
jj commit -m "Bootstrap Drift repo"
```

---

## 2. Minimal ARM64 Assembly Hello World

### 2.1 Directory structure

```bash
mkdir -p src
```

### 2.2 Write `src/hello.s`

This uses Linux ARM64 syscalls: `write` (64) and `exit` (93).

```asm
// src/hello.s

    .section .data
msg:
    .ascii  "Hello from Drift on ARM64!\n"
msg_end:

    .section .text
    .global _start

_start:
    // write(1, msg, len)
    mov     x0, #1              // fd = 1 (stdout)
    adr     x1, msg             // buf = &msg
    sub     x2, x1, x1          // x2 = 0
    add     x2, x2, #(msg_end - msg) // len = msg_end - msg
    mov     x8, #64             // sys_write = 64
    svc     #0                  // make syscall

    // exit(0)
    mov     x0, #0              // status = 0
    mov     x8, #93             // sys_exit = 93
    svc     #0
```

### 2.3 (Optional) Build locally inside a dev container

If you want a repeatable build environment, you can use Docker locally, but for
now we focus on building inside a Linux environment later. You can skip straight
to container-based builds in section 4.

Commit:

```bash
jj commit -m "Add initial ARM64 hello world assembly"
```

---

## 3. Add a `justfile` for Local Commands

Create `justfile` in project root:

```make
# justfile at project root

# Default recipe
default: help

help:
    @echo "Available recipes:"
    @echo "  build-image VERSION=dev    - Build Docker image for Drift (ARM64)"
    @echo "  push-image VERSION=dev     - Build and push image to GHCR"
    @echo "  deploy VERSION=dev         - Push image and restart Drift on OCI VM"

# Registry and image info
REGISTRY := ghcr.io
IMAGE_NS := your-github-username
IMAGE_NAME := drift
IMAGE := {{REGISTRY}}/{{IMAGE_NS}}/{{IMAGE_NAME}}
VERSION ?= dev

# Build ARM64 container image using Docker buildx
build-image:
    docker buildx build         --platform linux/arm64         -t {{IMAGE}}:{{VERSION}}         -t {{IMAGE}}:latest         .

# Push image to GHCR
push-image: build-image
    docker push {{IMAGE}}:{{VERSION}}
    docker push {{IMAGE}}:latest

# Drift deployment host (set real hostname or IP later)
DRIFT_HOST := ubuntu@your-drift-vm-ip-or-hostname

# Deploy: push image, then pull and restart on VM
deploy VERSION:
    just push-image VERSION={{VERSION}}
    ssh {{DRIFT_HOST}} '      sudo docker pull {{IMAGE}}:{{VERSION}} &&       sudo docker tag {{IMAGE}}:{{VERSION}} {{IMAGE}}:latest &&       (sudo docker stop drift || true) &&       (sudo docker rm drift || true) &&       sudo docker run -d --name drift -p 80:80 {{IMAGE}}:latest     '
```

_(You will fill in `your-github-username` and `DRIFT_HOST` later.)_

Commit:

```bash
jj commit -m "Add initial justfile with build/push/deploy placeholders"
```

---

## 4. Dockerfile for Drift (ARM64 Image)

Create `Dockerfile` in the project root:

```Dockerfile
# syntax=docker/dockerfile:1.7

#########################
# Build stage
#########################
FROM --platform=linux/arm64 ubuntu:24.04 AS build

RUN apt-get update &&     apt-get install -y clang lld make &&     rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Copy the source code
COPY src/ src/

# Build the Drift binary
RUN mkdir -p build &&     clang --target=aarch64-linux-gnu -nostdlib       -Wl,-e,_start -Wl,--gc-sections       -o build/drift src/hello.s

#########################
# Runtime stage
#########################
FROM --platform=linux/arm64 ubuntu:24.04

RUN useradd -m drift && mkdir -p /opt/drift && chown drift:drift /opt/drift

WORKDIR /opt/drift

COPY --from=build /src/build/drift /opt/drift/drift

USER drift

EXPOSE 80

CMD ["/opt/drift/drift"]
```

Test build locally (requires Docker buildx):

```bash
docker buildx build --platform linux/arm64 -t ghcr.io/your-github-username/drift:dev .
```

Commit:

```bash
jj commit -m "Add Dockerfile for Drift ARM64 image"
```

---

## 5. GitHub Container Registry (GHCR) Setup

1. Ensure your repo is in GitHub and you have `ghcr.io` access.
2. Create a Personal Access Token (Classic) or fine-grained token with
   `write:packages` scope.
3. Log in to GHCR:

```bash
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u your-github-username --password-stdin
```

4. Test `just` recipes:

```bash
# Build and push version v0.1.0
just push-image VERSION=v0.1.0
```

You should see the image appear at:

```
ghcr.io/your-github-username/drift:v0.1.0
ghcr.io/your-github-username/drift:latest
```

Commit:

```bash
jj commit -m "Configure container image build and push to GHCR"
```

---

## 6. GitHub Release with Binary Artifact

Later, you can publish the binary as a Release asset. For now, conceptually:

- Build a standalone binary (using same `clang` invocation as in Dockerfile)
  into `build/drift-linux-arm64`.
- Create a GitHub Release (e.g., `v0.1.0`) and upload:
  - `drift-linux-arm64`
  - A note that `ghcr.io/your-user/drift:v0.1.0` is the container image.

This keeps your distribution story consistent (binary + Docker).

---

## 7. OCI Account & Base VM Image with Packer

### 7.1 Create OCI Free Tier account

Do this once via browser:

- Go to <https://www.oracle.com/cloud/free/>
- Sign up, select home region, verify card, etc.
- Ensure your tenancy has access to **Always Free** Ampere A1 shapes.

### 7.2 Packer Setup

Inside `packer/`:

```bash
mkdir -p packer
cd packer
```

Create `oci.pkr.hcl` (this is a **template**; you’ll plug in real OCIDs):

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
  description = "OCID of an Ubuntu ARM64 base image (Always Free eligible)"
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
      "sudo systemctl start docker",
      "echo 'Base image ready with Docker installed for Drift.'"
    ]
  }
}
```

Initialize Packer plugins:

```bash
cd packer
packer init oci.pkr.hcl
```

Build the image (you’ll set variables via env or `-var` flags):

```bash
packer build   -var 'compartment_ocid=ocid1.compartment.oc1..xxxxx'   -var 'tenancy_ocid=ocid1.tenancy.oc1..xxxxx'   -var 'user_ocid=ocid1.user.oc1..xxxxx'   -var 'fingerprint=xx:xx:xx:...'   -var 'private_key_path=/path/to/oci_api_key.pem'   -var 'region=us-foo-1'   -var 'subnet_ocid=ocid1.subnet.oc1..xxxxx'   -var 'base_image_ocid=ocid1.image.oc1..xxxxx'   oci.pkr.hcl
```

Packer will output a **custom image OCID** you’ll use in Terraform (call it
`drift_image_ocid`).

Commit:

```bash
cd ..
jj commit -m "Add Packer template for OCI base image with Docker"
```

---

## 8. Terraform: Networking + VM Provisioning

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

############################
# Networking
############################

resource "oci_core_vcn" "drift_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "drift-vcn"
  cidr_block     = "10.0.0.0/16"
}

resource "oci_core_internet_gateway" "drift_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.drift_vcn.id
  display_name   = "drift-igw"
}

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

resource "oci_core_subnet" "drift_subnet" {
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.drift_vcn.id
  display_name        = "drift-subnet"
  cidr_block          = "10.0.1.0/24"
  route_table_id      = oci_core_route_table.drift_rt.id
  dns_label           = "driftsubnet"

  security_list_ids = [oci_core_security_list.drift_sl.id]
}

resource "oci_core_security_list" "drift_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.drift_vcn.id
  display_name   = "drift-security-list"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      destination_port_range {
        min = 80
        max = 80
      }
    }
  }

  # (Optional) Allow SSH
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

############################
# Drift ARM64 Instance
############################

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

Initialize:

```bash
cd terraform
terraform init
```

Plan & apply:

```bash
terraform plan   -var 'tenancy_ocid=ocid1.tenancy.oc1..xxxxx'   -var 'user_ocid=ocid1.user.oc1..xxxxx'   -var 'fingerprint=xx:xx:xx:...'   -var 'private_key_path=/path/to/oci_api_key.pem'   -var 'region=us-foo-1'   -var 'compartment_ocid=ocid1.compartment.oc1..xxxxx'   -var 'availability_domain=Uocm:PHX-AD-1'   -var 'drift_image_ocid=ocid1.image.oc1..xxxxx'

terraform apply   -var 'tenancy_ocid=...'   ...
```

Terraform will output `drift_public_ip`.

Commit:

```bash
cd ..
jj commit -m "Add Terraform config for Drift VCN and ARM64 instance"
```

---

## 9. First Deployment to OCI VM

### 9.1 SSH into the VM

Use the public IP from Terraform:

```bash
ssh ubuntu@<drift_public_ip>
```

Verify Docker is installed:

```bash
docker --version
sudo docker ps
```

### 9.2 Run the Drift container by hand

On the VM:

```bash
sudo docker login ghcr.io -u your-github-username
# enter token

sudo docker pull ghcr.io/your-github-username/drift:v0.1.0

sudo docker run -d --name drift -p 80:80 ghcr.io/your-github-username/drift:v0.1.0
```

Now on your local machine, hit:

```bash
curl http://<drift_public_ip>/
# or open in browser
```

You should see:

```text
Hello from Drift on ARM64!
```

---

## 10. Wire Up `just deploy`

Update `justfile` at project root with the real values:

```make
REGISTRY := ghcr.io
IMAGE_NS := your-github-username
IMAGE_NAME := drift
IMAGE := {{REGISTRY}}/{{IMAGE_NS}}/{{IMAGE_NAME}}
VERSION ?= dev

DRIFT_HOST := ubuntu@<drift_public_ip>
```

Now end-to-end:

```bash
# Make a code change in src/hello.s (e.g. tweak the message)
jj commit -m "Tweak Drift hello message"

# Deploy new version
just deploy VERSION=v0.1.1
```

This will:

1. Build the ARM64 image locally
2. Push `ghcr.io/your-github-username/drift:v0.1.1` and `:latest`
3. SSH into VM
4. Pull the new tag
5. Restart the `drift` container bound to port 80

Check again in browser or via curl.

---

## 11. Next Steps & Ideas

- Add a proper **HTTP response** (status line + headers + body) in assembly.
- Split code into multiple `.s` files and add a more robust build step.
- Build a small router or request parser in pure asm.
- Introduce **Rust interop**: Rust main calls assembly handler, or vice versa.
- Add a minimal CI job that:
  - Builds the ARM64 Docker image
  - Runs a basic integration test against it
  - Pushes to GHCR on tagged releases

---

You now have:

- A pure ARM64 assembly “hello world” binary
- A reproducible container image build
- A GHCR-hosted image registry
- An OCI ARM64 VM running your Drift container on port 80
- A `just deploy` command that ties it all together

Drift is officially live. 🚀
