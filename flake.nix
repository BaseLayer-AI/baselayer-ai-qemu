{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # The host system (your Apple Silicon Mac)
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      
      # The target architecture (the x86_64 Linux VM)
      x86_64_pkgs = import nixpkgs { system = "x86_64-linux"; };

      # We point to the package directory
      kernel_dir = x86_64_pkgs.linuxPackages.kernel;
      
      # We try the most common path for the initrd
      # initrd_path = x86_64_pkgs.linuxPackages.kernel.initrd;
    in {
      packages = {
        ${system}.default = pkgs.writeTextFile {
          name = "qemu-research";
          executable = true;
          destination = "/bin/qemu-research";
          text = ''
            #!${pkgs.stdenv.shell}

            BASE_DIR=$(pwd)
            LOG_PATH="$BASE_DIR/test.log"
            ERR_LOG="$BASE_DIR/qemu_error.log"

            # --- Cleanup Function ---
            cleanup() {
              echo "-----------------------------------------------------------"
              echo "Cleaning up..."
              rm -f "$LOG_PATH" "$ERR_LOG"
              echo "Done."
            }

            trap cleanup EXIT INT TERM

            # Clear the old log
            > "$LOG_PATH"

            echo "Starting QEMU Kernel-only boot (15s timeout)..."
            
            # 1. Start QEMU
            # Note: We use ${kernel_dir}/bzImage to point to the actual binary file
            ${pkgs.qemu}/bin/qemu-system-x86_64 \
              -kernel ${kernel_dir}/bzImage \
              -nographic \
              -display none \
              -serial file:"$LOG_PATH" \
              -append "console=ttyS0" \
              -m 512M \
              2> "$ERR_LOG" &
            
            QEMU_PID=$!

            # 2. Wait 15 seconds
            sleep 15

            # 3. Kill the process
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

