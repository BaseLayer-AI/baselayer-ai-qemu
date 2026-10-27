# baselayer-ai-qemu

## CI/CD Automated QEMU Kernel Verification Flake

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
The error check access for rdinit=/init failed: -2 when running via GitHub happens because the script uses BASE_DIR=$(pwd) to determine where it builds and looks for initrd.cpio.
When you run nix run github:..., Nix does not run the script inside your current working directory. Instead, it downloads the flake into a read-only sandboxed directory deep inside the Nix store (or a read-only evaluation cache) and executes it from there. Because the script tries to write initrd.cpio into $(pwd), it either silently fails to create it due to read-only permissions, or it creates it in a place that QEMU cannot access. QEMU then boots with a missing or empty initrd.cpio file, causing the kernel to panic.
Additionally, the command line parameter -initrd ./initrd.cpio uses a relative path. If QEMU runs in a different context, it will look for the file in the user's host working directory instead of the bundle generation directory.

The Fix

To make the flake completely location-independent so it works perfectly via both nix run . and remote URL lookups like nix run github:..., we must replace $(pwd) with a secure, temporary runtime directory via mktemp -d.
Here is the corrected flake.nix that uses secure runtime paths:

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
        # FIXED: Use a transient system temp directory instead of the read-only Nix store evaluation path
        WORK_DIR=$(mktemp -d)
        LOG_PATH="$WORK_DIR/test.log"
        ERR_LOG="$WORK_DIR/qemu_error.log"
        INITRD_PATH="$WORK_DIR/initrd.cpio"
        TMP_INITRD="$WORK_DIR/tmp_initrd"

        cleanup() {
          echo "Cleaning up temporary pipeline workspace..."
          rm -rf "$WORK_DIR"
          echo "Workspace clean."
        }

        # Ensure directory paths are cleaned up even if the runner fails or cancels
        trap cleanup EXIT INT TERM

        echo "--- Step 1: Building minimal initrd ---"
        mkdir -p "$TMP_INITRD/bin"
        mkdir -p "$TMP_INITRD/proc" "$TMP_INITRD/sys" "$TMP_INITRD/dev"
        mkdir -p "$TMP_INITRD/etc"
        
        cp "${busybox_static}/bin/busybox" "$TMP_INITRD/bin/busybox"
        chmod +x "$TMP_INITRD/bin/busybox"
        ln -sf busybox "$TMP_INITRD/bin/sh"

        cp "${busybox_static}/bin/busybox" "$TMP_INITRD/init"
        chmod +x "$TMP_INITRD/init"

        # Configured inittab to auto-verify the state and trigger an explicit system poweroff
        cat <<EOF > "$TMP_INITRD/etc/inittab"
::sysinit:/bin/busybox mount -t proc proc /proc
::sysinit:/bin/busybox mount -t sysfs sysfs /sys
::sysinit:/bin/busybox mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/busybox echo "--- Kernel successfully reached init script ---"
::sysinit:/bin/busybox poweroff -f
EOF

        # Pack the directory tree entries explicitly mapping out to the temp destination
        cd "$TMP_INITRD"
        find . ! -name "." | ${host.cpio}/bin/cpio -oH newc > "$INITRD_PATH"

        echo "--- Step 2: Running Automated QEMU Instance ---"
        > "$LOG_PATH"
        
        # FIXED: Changed -initrd to look up the full absolute path inside $WORK_DIR
        ${host.qemu}/bin/qemu-system-x86_64 \
          -cpu max \
          -kernel ${kernel_dir}/bzImage \
          -initrd "$INITRD_PATH" \
          -nographic \
          -display none \
          -no-reboot \
          -serial file:"$LOG_PATH" \
          -append "console=ttyS0 init=/init panic=-1" \
          -m 512M 2> "$ERR_LOG"

        echo "--- Step 3: Verifying Results ---"
        if [ -s "$LOG_PATH" ]; then
          cat "$LOG_PATH"
          if grep -q "Kernel successfully reached init" "$LOG_PATH"; then
            echo "CI STATUS: SUCCESS"
            exit 0
          else
            echo "CI STATUS: FAILURE (Message checkpoint missing)"
            exit 1
          fi
        else
          echo "CI STATUS: ERROR (Empty Log Layout)"
          # Print the error log before the trap removes it
          [ -f "$ERR_LOG" ] && cat "$ERR_LOG"
          exit 1
        fi
      '';
    };
}
```

What Changed?

• Decoupled from Host Paths: Changed the directory creation targets from $(pwd) to a dynamically generated isolation path $(mktemp -d). This bypasses read-only directory failures when evaluating remote GitHub targets.

• Absolute Asset Resolution: Replaced the relative QEMU lookups (-initrd ./initrd.cpio) with explicit absolute paths (-initrd "$INITRD_PATH"). This guarantees that QEMU locates the file regardless of the context it was launched from.

