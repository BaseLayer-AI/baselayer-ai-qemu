# baselayer-ai-qemu

```
nix run "https://flakehub.com/f/BaseLayer-AI/baselayer-ai-qemu/*"
```

```nix
{
  description = "A CI-optimized automation script to run an x86_64 guest kernel hearbeat check inside QEMU";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*";
  };

  outputs = { self, nixpkgs }:
    let
      aarch64-darwin = import nixpkgs { system = "aarch64-darwin"; };
      aarch64-linux = import nixpkgs { system = "aarch64-linux"; };
      x86_64-linux = import nixpkgs { system = "x86_64-linux"; };

      qemu-boot-busybox-kernel-heartbeat = { host, guest } :
        host.writeTextFile { name = "qemu-boot-busybox-kernel-heartbeat"; executable = true; destination = "/bin/qemu-boot-busybox-kernel-heartbeat";
        text = ''
#!${host.stdenv.shell}
BASE_DIR=$(pwd)
LOG_PATH="$BASE_DIR/test.log"
ERR_LOG="$BASE_DIR/qemu_error.log"

cleanup() {
  echo "Cleaning workspace artifacts..."
  rm -rf "$BASE_DIR/tmp_initrd"
  rm -f "$BASE_DIR/initrd.cpio"
  rm -f "$LOG_PATH" "$ERR_LOG"
  echo "Workspace clean."
}

trap cleanup EXIT INT TERM

echo "--- Step 1: Building minimal initrd ---"
mkdir -p "$BASE_DIR/tmp_initrd/bin"
mkdir -p "$BASE_DIR/tmp_initrd/proc" "$BASE_DIR/tmp_initrd/sys" "$BASE_DIR/tmp_initrd/dev"
mkdir -p "$BASE_DIR/tmp_initrd/etc"

cp "${guest.pkgsStatic.busybox}/bin/busybox" "$BASE_DIR/tmp_initrd/bin/busybox"
chmod +x "$BASE_DIR/tmp_initrd/bin/busybox"
ln -sf busybox "$BASE_DIR/tmp_initrd/bin/sh"

cp "${guest.pkgsStatic.busybox}/bin/busybox" "$BASE_DIR/tmp_initrd/init"
chmod +x "$BASE_DIR/tmp_initrd/init"

# Direct command calls in inittab (No shell used)
cat <<EOF > "$BASE_DIR/tmp_initrd/etc/inittab"
::sysinit:/bin/busybox mount -t proc proc /proc
::sysinit:/bin/busybox mount -t sysfs sysfs /sys
::sysinit:/bin/busybox mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/busybox cat /proc/version
::sysinit:/bin/busybox cat /proc/cpuinfo
::sysinit:/bin/busybox cat /proc/meminfo
::sysinit:/bin/busybox poweroff -f
EOF

# Pack the directory tree entries
cd "$BASE_DIR/tmp_initrd"
find . ! -name "." | ${host.cpio}/bin/cpio -oH newc > "$BASE_DIR/initrd.cpio"
cd "$BASE_DIR"

echo "--- Step 2: Running Automated QEMU Instance ---"
> "$LOG_PATH"
        
${host.qemu}/bin/qemu-system-x86_64 -cpu max -kernel ${guest.linuxPackages.kernel}/bzImage -initrd ./initrd.cpio -nographic -display none -no-reboot -serial file:"$LOG_PATH" -append "console=ttyS0 init=/init panic=-1" -m 512M 2> "$ERR_LOG"

echo "--- Step 3: Verifying Results ---"
if [ -s "$LOG_PATH" ]; then
  echo "--- Captured Guest Logs ---"
  cat -n "$LOG_PATH"
          
  # Verify that the specific system files were read successfully
  if grep -q "Linux version" "$LOG_PATH" && grep -q "model name" "$LOG_PATH" && grep -q "MemTotal" "$LOG_PATH"; then
    echo "CI STATUS: SUCCESS"
    exit 0
  else
    echo "CI STATUS: FAILURE (Diagnostics missing from log)"
    exit 1
  fi
else
  echo "CI STATUS: ERROR (Empty Log Layout)"
  [ -f "$ERR_LOG" ] && cat -n "$ERR_LOG"
  exit 1
fi
        '';};
  in {
      packages.aarch64-darwin.default = qemu-boot-busybox-kernel-heartbeat { host = aarch64-darwin; guest = x86_64-linux; };
      packages.aarch64-linux.default = qemu-boot-busybox-kernel-heartbeat { host = aarch64-linux; guest = x86_64-linux; };
      packages.x86_64-linux.default = qemu-boot-busybox-kernel-heartbeat { host = x86_64-linux; guest = x86_64-linux; };
  };
}

```

This script is a **CI (Continuous Integration) "Smoke Test"** designed to verify that a specific Linux kernel can successfully boot and initialize basic system components.

Here is the breakdown of the **What**, **How**, and **Why**.

---

### 1. What is it?
It is a **Nix expression** that generates a shell script. This script automates the process of spinning up a virtual machine (VM) using QEMU. 

Instead of booting a full operating system (like Ubuntu or Fedora), it boots a **minimal "Initrd" (Initial Ramdisk)**. The goal is to reach a "heartbeat" state: verifying that the kernel can load, mount essential filesystems (`/proc`, `/sys`, `/dev`), and execute basic commands to report system information.

### 2. How does it work?
The script follows a four-stage pipeline:

#### A. Nix Environment Setup
The script uses Nix to handle cross-platform compatibility. It defines three host types (`aarch64-darwin`, `aarch64-linux`, `x86_64-linux`). Regardless of which machine is running the test (e.g., an Apple Silicon Mac or a standard Linux server), Nix ensures the correct QEMU binaries and the correct x86_64 Linux kernel are fetched.

#### B. The "Initrd" Construction (Step 1 in the script)
Before launching QEMU, the script builds a tiny filesystem from scratch:
1.  **Create Folders:** It creates a temporary directory structure (`/bin`, `/proc`, `/sys`, etc.).
2.  **Inject BusyBox:** It places a static `busybox` binary (a Swiss-army knife of Unix utilities) into the folder.
3.  **Configure `inittab`:** It creates an `inittab` file that tells the kernel: *"Once you boot, mount these three filesystems and then print the kernel version, CPU model, and Memory total."*
4.  **Package:** It uses `cpio` to compress this folder into a `.cpio` file, which is the standard format for a Linux Initrd.

#### C. The QEMU Execution (Step 2)
It launches `qemu-system-x86_64` with specific flags:
*   **`-kernel`**: Points to the actual Linux kernel (`bzImage`).
*   **`-initrd`**: Points to the `.cpio` file created in the previous step.
*   **`-serial file:"$LOG_PATH"`**: This is crucial. It redirects everything the guest kernel prints to a text file on the host machine.
*   **`-nographic -display none`**: Ensures the test runs in a "headless" mode (no window pops up), which is required for CI servers.

#### D. Verification (Step 3)
The script doesn't just run QEMU and assume it worked. It parses the resulting `test.log` file. 
*   If the log contains "Linux version", "model name", and "MemTotal", it means the kernel successfully booted and ran the commands.
*   If these strings are missing, the script exits with an error code (`1`), failing the CI build.

---

### 3. Why is it built this way?

**1. Speed (The "Smoke Test" Philosophy)**
Booting a full Linux distribution in CI takes minutes. Booting a kernel with an Initrd takes **seconds**. This allows developers to get instant feedback on whether a kernel change broke the basic ability to boot.

**2. Determinism (The "Nix" Philosophy)**
By using Nix, the script ensures that the **exact same** kernel binary and `busybox` version are used every single time. This eliminates "it works on my machine" bugs where a different version of QEMU or a different kernel header might be installed on the host.

**3. Portability**
The script handles the complexity of running an x86_64 guest on an ARM64 host (like an M1/M2/M3 Mac). It automatically selects the correct emulation path based on the machine's architecture.

**4. Automated Diagnostics**
By capturing the output to `test.log` and `qemu_error.log`, if the test fails, the CI system can print the exact error message from the kernel's "panic" screen, making it much easier for developers to debug.


GHA CI: <https://github.com/BaseLayer-AI/baselayer-ai-qemu/actions?query=branch%3Amain>

Full llama.cpp script: <https://nix-ontouchstart.github.io/nix-ontouchstart-llama_cpp-sessions/2026-11-03_02-29-51_conv_19f3d331_what_how_and_why_>
