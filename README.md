# baselayer-ai-qemu

```
nix run github:BaseLayer-AI/baselayer-ai-qemu/aarch64-darwin-qemu-boot-busybox
```

# CI/CD Automated QEMU Kernel Verification Flake

This directory contains a self-contained, zero-build Nix flake designed to verify that an `x86_64-linux` kernel can successfully boot and reach its initialization phase. It is fully optimized for automated CI/CD runners on Apple Silicon (`aarch64-darwin`) host machines.

## Core Features
* **Zero Host Builds:** Downloads pre-compiled `x86_64-linux` kernel and static `busybox` components instantly from the official Nix binary cache.
* **Deterministic Lifecycle:** Uses QEMU's `-no-reboot` flag coupled with a guest-side `poweroff -f` to execute completely synchronously without flaky time-based `sleep` hacks.
* **CI Clean Exit Paths:** Automatically isolates, prints, and wipes all runtime log traces (`test.log`, `qemu_error.log`, and cpio archives) via process shell traps to prevent workspace leakage across subsequent pipeline stages.

## The `flake.nix` Configuration

Save the following content precisely as `flake.nix`:

```nix
{
  description = "A CI-optimized automation script to run an x86_64 guest kernel verification check inside QEMU";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
  };

  outputs = { self, nixpkgs }:
    let
      host = import nixpkgs { system = "aarch64-darwin"; };
      
      # Pull pre-compiled kernel artifact from the cache
      guestLinuxPkgs = (import nixpkgs { system = "x86_64-linux"; }).linuxPackages;
      kernel_dir = guestLinuxPkgs.kernel;

      # Pull pre-compiled static busybox directly from Nix cache (zero compilation)
      guestStaticPkgs = import nixpkgs { system = "x86_64-linux"; };
      busybox_static = guestStaticPkgs.pkgsStatic.busybox;
    in {
      packages.aarch64-darwin.default = host.writeShellScriptBin "qemu-boot-initrd" ''
        BASE_DIR=\$(pwd)
        LOG_PATH="\$BASE_DIR/test.log"
        ERR_LOG="\$BASE_DIR/qemu_error.log"

        cleanup() {
          echo "Cleaning workspace artifacts..."
          rm -rf "\$BASE_DIR/tmp_initrd"
          rm -f "\$BASE_DIR/initrd.cpio"
          rm -f "\(LOG_PATH" "\)ERR_LOG"
          echo "Workspace clean."
        }

        # Ensure everything is cleaned up if the runner is cancelled or fails mid-run
        trap cleanup EXIT INT TERM

        echo "--- Step 1: Building minimal initrd ---"
        mkdir -p "\$BASE_DIR/tmp_initrd/bin"
        mkdir -p "\$BASE_DIR/tmp_initrd/proc" "\(BASE_DIR/tmp_initrd/sys" "\)BASE_DIR/tmp_initrd/dev"
        mkdir -p "\$BASE_DIR/tmp_initrd/etc"
        
        cp "\({busybox_static}/bin/busybox" "\)BASE_DIR/tmp_initrd/bin/busybox"
        chmod +x "\$BASE_DIR/tmp_initrd/bin/busybox"
        ln -sf busybox "\$BASE_DIR/tmp_initrd/bin/sh"

        cp "\({busybox_static}/bin/busybox" "\)BASE_DIR/tmp_initrd/init"
        chmod +x "\$BASE_DIR/tmp_initrd/init"

        # Configured inittab to auto-verify the state and trigger an explicit system poweroff
        cat <<EOF > "\$BASE_DIR/tmp_initrd/etc/inittab"
::sysinit:/bin/busybox mount -t proc proc /proc
::sysinit:/bin/busybox mount -t sysfs sysfs /sys
::sysinit:/bin/busybox mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/busybox echo "--- Kernel successfully reached init script ---"
::sysinit:/bin/busybox poweroff -f
EOF

        # Pack the directory tree entries
        cd "\$BASE_DIR/tmp_initrd"
        find . ! -name "." | \${host.cpio}/bin/cpio -oH newc > "\$BASE_DIR/initrd.cpio"
        cd "\$BASE_DIR"

        echo "--- Step 2: Running Automated QEMU Instance ---"
        > "\$LOG_PATH"
        
        # Added -no-reboot so that when the guest calls poweroff, QEMU shuts down and returns control instantly
        \${host.qemu}/bin/qemu-system-x86_64 \
          -cpu max \
          -kernel \${kernel_dir}/bzImage \
          -initrd ./initrd.cpio \
          -nographic \
          -display none \
          -no-reboot \
          -serial file:"\$LOG_PATH" \
          -append "console=ttyS0 init=/init panic=-1" \
          -m 512M 2> "\$ERR_LOG"

        echo "--- Step 3: Verifying Results ---"
        if [ -s "\$LOG_PATH" ]; then
          cat "\$LOG_PATH"
          if grep -q "Kernel successfully reached init" "\$LOG_PATH"; then
            echo "CI STATUS: SUCCESS"
            exit 0
          else
            echo "CI STATUS: FAILURE (Message checkpoint missing)"
            exit 1
          fi
        else
          echo "CI STATUS: ERROR (Empty Log Layout)"
          # Print the error log before the trap removes it
          [ -f "\(ERR_LOG" ] && cat "\)ERR_LOG"
          exit 1
        fi
      '';
    };
}
```

## How to Run locally or in CI/CD Pipelines

Because Nix flakes parse workspace components deterministically, any code updates must be indexed by Git before execution.

```bash
# 1. Initialize repository tracking if starting fresh
git init

# 2. Stage the flake environment configuration file 
git add flake.nix

# 3. Trigger the headless execution check
nix run .
```

