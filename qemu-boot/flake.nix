{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/master";
  outputs = { self, nixpkgs }:
    let
      host = import nixpkgs { system = "aarch64-darwin"; };
      guest = import nixpkgs { system = "x86_64-linux"; };
      kernel_dir = guest.linuxPackages.kernel;
    in {
      packages = {
        aarch64-darwin.default = host.writeTextFile {
          name = "qemu-boot";
          executable = true;
          destination = "/bin/qemu-boot";
          text = ''
            #!${host.stdenv.shell}

            BASE_DIR=$(pwd)
            LOG_PATH="$BASE_DIR/test.log"
            ERR_LOG="$BASE_DIR/qemu_error.log"

            cleanup() {
              echo "-----------------------------------------------------------"
              echo "Cleaning up..."
              rm -f "$LOG_PATH" "$ERR_LOG"
              echo "Done."
            }

            trap cleanup EXIT INT TERM

            > "$LOG_PATH"

            echo "Starting QEMU Kernel + Initrd boot (15s timeout)..."
            
            # 1. Start QEMU
            ${host.qemu}/bin/qemu-system-x86_64 \
              -kernel ${kernel_dir}/bzImage \
              -nographic \
              -display none \
              -serial file:"$LOG_PATH" \
              -append "console=ttyS0 root=/dev/null" \
              -m 512M \
              2> "$ERR_LOG" &
            
            QEMU_PID=$!

            sleep 15

            echo "Killing QEMU (PID: $QEMU_PID)..."
            kill $QEMU_PID 2>/dev/null || true

            sleep 0.5

            echo "-----------------------------------------------------------"
            echo "Kernel Boot Log Content:"
            if [ -s "$LOG_PATH" ]; then
              cat "$LOG_PATH"
            else
              echo "Warning: $LOG_PATH is still empty."
              if [ -f "$ERR_LOG" ]; then
                echo "Startup Errors:"
                cat "$ERR_LOG"
              fi
            fi
            echo "-----------------------------------------------------------"

            true
          '';
        };
      };
    };
}
