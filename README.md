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

<https://github.com/BaseLayer-AI/baselayer-ai-qemu/actions?query=branch%3Amain>
