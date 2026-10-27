{
  description = "A CI-optimized automation script to run an x86_64 guest kernel verification check inside QEMU";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
  };

  outputs = { self, nixpkgs }:
    let
      host = import nixpkgs { system = "aarch64-darwin"; };
      guestStaticPkgs = import nixpkgs { system = "x86_64-linux"; };
      
      kernel_dir = guestStaticPkgs.linuxPackages.kernel;
      busybox_static = guestStaticPkgs.pkgsStatic.busybox;

      # FIXED: Clean root layout for the cpio archive
      initrd = host.runCommand "guest-initrd.cpio" {
        nativeBuildInputs = [ host.cpio ];
      } ''
        mkdir -p root/bin root/proc root/sys root/dev root/etc
        
        cp "${busybox_static}/bin/busybox" root/bin/busybox
        chmod +x root/bin/busybox
        ln -sf busybox root/bin/sh
        cp "${busybox_static}/bin/busybox" root/init
        chmod +x root/init

        cat <<EOF > root/etc/inittab
::sysinit:/bin/busybox mount -t proc proc /proc
::sysinit:/bin/busybox mount -t sysfs sysfs /sys
::sysinit:/bin/busybox mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/busybox echo "--- Kernel successfully reached init script ---"
::sysinit:/bin/busybox poweroff -f
EOF

        # Safely pack from inside the root folder so /init is at the filesystem root
        cd root
        find . -print0 | cpio --null -ov -H newc > $out
      '';

    in {
      packages.aarch64-darwin.default = host.writeShellScriptBin "qemu-boot-busybox" ''
        set -euo pipefail

        BASE_DIR=$(pwd)
        LOG_PATH="$BASE_DIR/test.log"
        ERR_LOG="$BASE_DIR/qemu_error.log"

        cleanup() {
          rm -f "$LOG_PATH" "$ERR_LOG"
        }
        trap cleanup EXIT INT TERM

        echo "--- Step 1: Running Automated QEMU Instance ---"
        > "$LOG_PATH"
        
        ${host.qemu}/bin/qemu-system-x86_64 \
          -cpu max \
          -kernel ${kernel_dir}/bzImage \
          -initrd ${initrd} \
          -nographic \
          -display none \
          -no-reboot \
          -serial file:"$LOG_PATH" \
          -append "console=ttyS0 init=/init panic=-1" \
          -m 512M 2> "$ERR_LOG"

        echo "--- Step 2: Verifying Results ---"
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
          [ -f "$ERR_LOG" ] && cat "$ERR_LOG"
          exit 1
        fi
      '';
    };
}

