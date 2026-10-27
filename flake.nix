{
  description = "A CI-optimized automation script to run an x86_64 guest kernel hearbeat check inside QEMU";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
  };

  outputs = { self, nixpkgs }:
    let
      host = import nixpkgs { system = "x86_64-linux"; };
      
      # Pull pre-compiled kernel artifact from the cache
      guestLinuxPkgs = (import nixpkgs { system = "x86_64-linux"; }).linuxPackages;
      kernel_dir = guestLinuxPkgs.kernel;

      # Pull pre-compiled static busybox directly from Nix cache
      guestStaticPkgs = import nixpkgs { system = "x86_64-linux"; };
      busybox_static = guestStaticPkgs.pkgsStatic.busybox;
    in {
      packages.x86_64-linux.default = host.writeShellScriptBin "qemu-boot-busybox-kernel-heartbeat" ''
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
        
        cp "${busybox_static}/bin/busybox" "$BASE_DIR/tmp_initrd/bin/busybox"
        chmod +x "$BASE_DIR/tmp_initrd/bin/busybox"
        ln -sf busybox "$BASE_DIR/tmp_initrd/bin/sh"

        cp "${busybox_static}/bin/busybox" "$BASE_DIR/tmp_initrd/init"
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
        
        ${host.qemu}/bin/qemu-system-x86_64 \
          -cpu max \
          -kernel ${kernel_dir}/bzImage \
          -initrd ./initrd.cpio \
          -nographic \
          -display none \
          -no-reboot \
          -serial file:"$LOG_PATH" \
          -append "console=ttyS0 init=/init panic=-1" \
          -m 512M 2> "$ERR_LOG"

        echo "--- Step 3: Verifying Results ---"
        if [ -s "$LOG_PATH" ]; then
          echo "--- Captured Guest Logs ---"
          cat "$LOG_PATH"
          
          # Verify that the specific system files were read successfully
          if grep -q "Linux version" "$LOG_PATH" && \
             grep -q "model name" "$LOG_PATH" && \
             grep -q "MemTotal" "$LOG_PATH"; then
            echo "CI STATUS: SUCCESS"
            exit 0
          else
            echo "CI STATUS: FAILURE (Diagnostics missing from log)"
            exit 1
          fi
        else
          echo "CI STATUS: ERROR (Empty Log Layout)"
          [ -f "$ERR_LOG" ] && cat "$ERR_LOG"
          exit 1
        fi
      '';
    };
}

