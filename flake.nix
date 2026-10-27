{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/master";

  outputs = { self, nixpkgs }:
    let
      host = import nixpkgs { system = "aarch64-darwin"; };
      guest = import nixpkgs { system = "aarch64-linux"; };
    in {
      packages = {
        aarch64-darwin.default = host.writeTextFile {
          name = "qemu-aarch64-explore";
          executable = true;
          destination = "/bin/qemu-aarch64-explore";
          text = ''
            #!${host.stdenv.shell}
            BASE_DIR=$(pwd)
            LOG="$BASE_DIR/std.log"
            ERR="$BASE_DIR/err.log"

            cleanup() {
              echo "Cleaning up..."
              cat -n "$LOG"
              cat -n "$ERR"
              rm -f "$LOG" "$ERR"
              echo "Done."
            }
            
            trap cleanup EXIT INT TERM

            # We use -kernel for the binary and -append to tell the kernel 
            # what to do (since there is no hard drive yet)
            ${host.qemu}/bin/qemu-system-aarch64 \
              -machine virt \
              -cpu max \
              -smp 4 \
              -m 2G \
              -kernel ${guest.linuxKernel.kernels.linux_6_12}/Image \
              -append "console=ttyAMA0" \
              -nographic > "$LOG" 2> "$ERR" &
            
            QEMU_PID=$!

            sleep 15

            echo "Killing QEMU (PID: $QEMU_PID)..."
            kill $QEMU_PID 2>/dev/null || true

          '';

        };
      };
    };
}

